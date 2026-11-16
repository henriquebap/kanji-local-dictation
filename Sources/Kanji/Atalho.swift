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
            .filter { modificadores & UInt32($0.0) != 0 }.map(\.1).joined()
            + (tecla == "Espaço" ? String(localized: "Espaço") : tecla)  // "Espaço" fica gravado assim no UserDefaults
    }

    init(keyCode: Int, modificadores: Int, tecla: String) {
        self.keyCode = UInt32(keyCode)
        self.modificadores = UInt32(modificadores)
        self.tecla = tecla
    }

    /// Atalho global só com ⌃⌥ (⇧ e ⌘ podem somar). Os outros brigam com algo que a pessoa usa:
    /// - ⌘ e ⇧⌘ são dos menus dos apps, e o atalho global ganha deles: com ⇧⌘T gravado, "reabrir aba" parou nos
    ///   navegadores, e o ⇧⌘D gravado aqui é "enviar" no Mail;
    /// - ⌃ sozinho edita texto (⌃D apaga, ⌃K corta até o fim da linha);
    /// - ⌥ sozinho digita acentos e símbolos.
    /// O macOS não usa ⌃⌥ + letra, e nenhum app instalado neste Mac registrava uma.
    var semConflito: Bool {
        modificadores & UInt32(controlKey | optionKey) == UInt32(controlKey | optionKey)
    }

    /// nil sem ⌃⌥ (veja `semConflito`): o gravador continua esperando.
    init?(evento: NSEvent) {
        let f = evento.modifierFlags
        guard f.contains([.control, .option]) else { return nil }
        let pares: [(NSEvent.ModifierFlags, Int)] = [(.command, cmdKey), (.option, optionKey), (.control, controlKey), (.shift, shiftKey)]
        let mods = pares.filter { f.contains($0.0) }.reduce(0) { $0 | $1.1 }
        // ponytail: F-keys e setas aparecem como caractere privado; mapear se alguém usar
        let c = evento.charactersIgnoringModifiers ?? "?"
        self.init(keyCode: Int(evento.keyCode), modificadores: mods, tecla: c == " " ? "Espaço" : c.uppercased())
    }
}

/// O que cada atalho global faz.
enum Acao: UInt32, CaseIterable {
    case ditar = 1, abrir = 2, cancelar = 3, transcrever = 4

    var padrao: Atalho {
        switch self {
        case .ditar: Atalho(keyCode: kVK_ANSI_D, modificadores: controlKey | optionKey, tecla: "D")  // D de ditar
        case .abrir: Atalho(keyCode: kVK_ANSI_K, modificadores: controlKey | optionKey, tecla: "K")  // K de Kanji
        case .cancelar: Atalho(keyCode: kVK_Escape, modificadores: 0, tecla: "esc")
        case .transcrever: Atalho(keyCode: kVK_ANSI_M, modificadores: controlKey | optionKey, tecla: "M")  // M de Mac
        }
    }

    private var chave: String { "atalho.\(rawValue)" }

    /// Um atalho gravado antes da regra do ⌃⌥ (⇧⌘D, ⇧⌘T) volta para o padrão.
    var atalho: Atalho {
        UserDefaults.standard.data(forKey: chave)
            .flatMap { try? JSONDecoder().decode(Atalho.self, from: $0) }
            .flatMap { $0.semConflito ? $0 : nil } ?? padrao
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
            registro.error("atalho \(atalho.descricao, privacy: .public) indisponível (\(status))")
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
    static let transcrever = GravadorDeAtalho(.transcrever)

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
            Button(gravador.gravando ? String(localized: "Pressione ⌃⌥ e uma letra…") : gravador.atalho.descricao) { gravador.alternar() }
                .frame(minWidth: 150)
        }
        .onDisappear { if gravador.gravando { gravador.parar() } }
    }
}
