import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Combinação de teclas guardada no UserDefaults (códigos do Carbon).
struct Atalho: Codable, Equatable {
    let keyCode: UInt32
    let modificadores: UInt32
    let tecla: String  // só para exibir

    var descricao: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modificadores & UInt32($0.0) != 0 }.map(\.1).joined() + tecla
    }

    init(keyCode: Int, modificadores: Int, tecla: String) {
        self.keyCode = UInt32(keyCode)
        self.modificadores = UInt32(modificadores)
        self.tecla = tecla
    }

    /// nil se não houver ⌘, ⌃ ou ⌥: atalho global só com Shift ou sem modificador roubaria a digitação normal.
    init?(evento: NSEvent) {
        let f = evento.modifierFlags
        guard !f.intersection([.command, .control, .option]).isEmpty else { return nil }
        let pares: [(NSEvent.ModifierFlags, Int)] = [(.command, cmdKey), (.option, optionKey), (.control, controlKey), (.shift, shiftKey)]
        let mods = pares.filter { f.contains($0.0) }.reduce(0) { $0 | $1.1 }
        // ponytail: F-keys e setas aparecem como caractere privado; mapear se alguém usar
        let c = evento.charactersIgnoringModifiers ?? "?"
        self.init(keyCode: Int(evento.keyCode), modificadores: mods, tecla: c == " " ? "Espaço" : c.uppercased())
    }
}

/// O que cada atalho global faz.
enum Acao: UInt32, CaseIterable {
    case ditar = 1, abrir = 2, cancelar = 3

    var padrao: Atalho {
        switch self {
        case .ditar: Atalho(keyCode: kVK_ANSI_D, modificadores: controlKey | optionKey, tecla: "D")
        case .abrir: Atalho(keyCode: kVK_ANSI_T, modificadores: controlKey | optionKey, tecla: "T")
        case .cancelar: Atalho(keyCode: kVK_Escape, modificadores: 0, tecla: "esc")
        }
    }

    private var chave: String { "atalho.\(rawValue)" }

    var atalho: Atalho {
        UserDefaults.standard.data(forKey: chave).flatMap { try? JSONDecoder().decode(Atalho.self, from: $0) } ?? padrao
    }

    func salvar(_ atalho: Atalho) {
        UserDefaults.standard.set(try? JSONEncoder().encode(atalho), forKey: chave)
    }
}

/// Atalhos globais via Carbon: funcionam com o app em segundo plano e não pedem permissão de Acessibilidade.
@MainActor
final class AtalhoGlobal {
    static let shared = AtalhoGlobal()

    var aoPressionar: (Acao) -> Void = { _ in }
    var aoSoltar: (Acao) -> Void = { _ in }
    private var refs: [Acao: EventHotKeyRef] = [:]

    private init() {
        var tipos = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, evento, _ in
            var id = EventHotKeyID()
            GetEventParameter(evento, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let pressionou = GetEventKind(evento) == UInt32(kEventHotKeyPressed)
            MainActor.assumeIsolated {
                guard let acao = Acao(rawValue: id.id) else { return }
                pressionou ? AtalhoGlobal.shared.aoPressionar(acao) : AtalhoGlobal.shared.aoSoltar(acao)
            }
            return noErr
        }, tipos.count, &tipos, nil, nil)
    }

    func registrar(_ acao: Acao) {
        desregistrar(acao)
        let atalho = acao.atalho
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4B41_4E4A), id: acao.rawValue)  // 'KANJ'
        let status = RegisterEventHotKey(atalho.keyCode, atalho.modificadores, id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            refs[acao] = ref
        } else {
            NSLog("Kanji: atalho \(atalho.descricao) indisponível (\(status))")
        }
    }

    func desregistrar(_ acao: Acao) {
        if let ref = refs.removeValue(forKey: acao) { UnregisterEventHotKey(ref) }
    }
}

/// Grava a próxima combinação de teclas pressionada para uma ação.
/// ponytail: classe @Observable em vez de @State porque a macro do SwiftUI só vem com o Xcode completo.
@MainActor @Observable
final class GravadorDeAtalho {
    static let ditar = GravadorDeAtalho(.ditar)
    static let abrir = GravadorDeAtalho(.abrir)

    let acao: Acao
    private(set) var atalho: Atalho
    private(set) var gravando = false
    @ObservationIgnored private var monitor: Any?

    private init(_ acao: Acao) {
        self.acao = acao
        atalho = acao.atalho
    }

    func alternar() {
        gravando ? parar() : gravar()
    }

    func aplicar(_ novo: Atalho) {
        atalho = novo
        acao.salvar(novo)
        parar()
    }

    func parar() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        gravando = false
        AtalhoGlobal.shared.registrar(acao)
    }

    private func gravar() {
        gravando = true
        AtalhoGlobal.shared.desregistrar(acao)  // senão o atalho atual dispara a ação em vez de ser gravado
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { evento in
            if evento.keyCode == UInt16(kVK_Escape) {
                self.parar()
            } else if let novo = Atalho(evento: evento) {
                self.aplicar(novo)
            }
            return nil
        }
    }
}

struct CampoDeAtalho: View {
    let gravador: GravadorDeAtalho

    var body: some View {
        HStack {
            if gravador.atalho != gravador.acao.padrao && !gravador.gravando {
                Button("Padrão") { gravador.aplicar(gravador.acao.padrao) }
                    .buttonStyle(.borderless)
            }
            Button(gravador.gravando ? "Pressione as teclas…" : gravador.atalho.descricao) { gravador.alternar() }
                .frame(minWidth: 150)
        }
        .onDisappear { if gravador.gravando { gravador.parar() } }
    }
}
