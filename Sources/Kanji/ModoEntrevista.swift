import AppKit
import SwiftUI

/// Modo entrevista ao vivo: durante a transcrição do Mac, quando o entrevistador pergunta, um painel mostra tópicos
/// tirados das notas de carreira. O entrevistador é o áudio do Mac; o candidato, o microfone numa chamada ("Você").
@MainActor @Observable
final class ModoEntrevista {
    private(set) var pergunta: String?
    private(set) var sugestao: String?
    private(set) var pensando = false
    private(set) var aviso: String?

    @ObservationIgnored private var ligado = false
    @ObservationIgnored private var notas: String?
    @ObservationIgnored private var inicioDaSessao = Date()
    /// O turno do entrevistador desde a última fala do candidato, nos dois reconhecedores.
    @ObservationIgnored private var pt: [Palavra] = []
    @ObservationIgnored private var en: [Palavra] = []
    @ObservationIgnored private var ultimaDisparada: String?
    @ObservationIgnored private var tarefa: Task<Void, Never>?
    /// A chave do provedor, lida em segundo plano no começo da sessão: a primeira leitura do Keychain levou de 7 a
    /// 13 s na thread principal e atrasava a primeira pergunta (medido). Fica só na memória, durante a sessão.
    @ObservationIgnored private var chave: Task<String?, Never>?
    @ObservationIgnored private lazy var painel = PainelDaEntrevista(modo: self)

    /// Lê as notas uma vez por sessão: o mesmo pacote a cada pergunta mantém o cache do provedor.
    func comecar(em inicio: Date) {
        (pt, en, ultimaDisparada, pergunta, sugestao, aviso, inicioDaSessao) = ([], [], nil, nil, nil, nil, inicio)
        ligado = UserDefaults.standard.bool(forKey: Ajustes.sugerirNaEntrevista)
        guard ligado else { return }
        guard let caminho = UserDefaults.standard.string(forKey: Ajustes.pastaDasNotas) else {
            notas = nil
            return avisar(String(localized: "Escolha a pasta de notas em Ajustes › Entrevista."))
        }
        do {
            notas = try Notas.ler(URL(filePath: caminho, directoryHint: .isDirectory)).pacote
            Correcao.aquecer()  // o detector usa o modelo do Mac: a primeira classificação sai mais rápida
            chave = Nuvem.pronto.map { p in
                Task.detached {
                    let comeco = Date.now
                    let chave = Chaveiro.ler(p)
                    registro.notice("entrevista: chave lida em \(Date.now.timeIntervalSince(comeco), format: .fixed(precision: 1)) s")
                    return chave
                }
            }
        } catch {
            registro.error("notas ilegíveis: \(error.localizedDescription, privacy: .private)")
            notas = nil
            avisar(String(localized: "Não consegui ler as notas: \(error.localizedDescription)"))
        }
    }

    func terminar() {
        tarefa?.cancel()
        chave = nil
        ligado = false
        painel.esconder()
    }

    func ouvirIngles(_ palavras: [Palavra]) {
        guard ligado else { return }
        en += palavras
    }

    /// O português firma ~2 s depois do fim da fala e o inglês ~1 s (medido com `.fastResults`): quando o português
    /// chega, o inglês do mesmo trecho já está aqui, e a fusão escolhe o idioma pela confiança.
    func ouvirPortugues(_ palavras: [Palavra]) {
        guard ligado, notas != nil, let fim = palavras.last?.fim else { return }
        pt += palavras
        // ponytail: só os últimos 90 s do turno; um entrevistador que fala mais que isso sem pausa para resposta
        // teria o começo cortado.
        (pt, en) = (pt.filter { $0.fim > fim - 90 }, en.filter { $0.fim > fim - 90 })
        let turno = Fusao.fundir(pt: pt, en: en, glossario: Ditado.glossario)
        // A mesma última frase já gerou tópicos: o entrevistador só continuou falando depois dela.
        guard let ultima = Pergunta.frases(turno).last, ultima != ultimaDisparada else { return }
        let comeco = Date.now
        Task {
            guard await Pergunta.pedeRespostaComModelo(turno), ultima != ultimaDisparada else { return }
            ultimaDisparada = ultima
            sugerir(turno, fimDaFala: fim, detector: Date.now.timeIntervalSince(comeco))
        }
    }

    /// O candidato começou a responder: o próximo turno do entrevistador começa do zero.
    func candidatoFalou() {
        (pt, en) = ([], [])
    }

    /// Atalho: pede tópicos para o turno atual, mesmo que o detector não tenha achado pergunta nele.
    func pedirAgora() {
        guard ligado, notas != nil else {
            return avisar(Kanji.shared.sessao.ativa
                ? String(localized: "Ligue as sugestões em Ajustes › Entrevista e comece a transcrição de novo.")
                : String(localized: "Comece a transcrição do Mac (\(Acao.transcrever.atalho.descricao)) durante a entrevista."))
        }
        let turno = Fusao.fundir(pt: pt, en: en, glossario: Ditado.glossario)
        guard turno.contains(where: \.isLetter) else { return avisar(String(localized: "Ainda não ouvi o entrevistador.")) }
        ultimaDisparada = Pergunta.frases(turno).last
        sugerir(turno, fimDaFala: (pt + en).map(\.fim).max() ?? 0, detector: 0)
    }

    func fechar() {
        painel.esconder()
    }

    private func sugerir(_ turno: String, fimDaFala: Double, detector: Double) {
        guard let notas else { return }
        tarefa?.cancel()  // a pergunta nova vale mais que a anterior
        (pergunta, sugestao, aviso, pensando) = (Pergunta.frases(turno).last ?? turno, nil, nil, true)
        painel.mostrar()
        tarefa = Task {
            let comeco = Date.now
            do {
                let texto = try await Nuvem.perguntar(turno, notas: notas, chave: await chave?.value)
                guard !Task.isCancelled else { return }
                sugestao = texto
                // Do fim da fala do entrevistador (relógio do áudio) até os tópicos na tela.
                let total = Date.now.timeIntervalSince(inicioDaSessao) - fimDaFala
                registro.notice("entrevista: tópicos \(total, format: .fixed(precision: 1)) s depois da pergunta (detector \(detector, format: .fixed(precision: 2)) s, nuvem \(Date.now.timeIntervalSince(comeco), format: .fixed(precision: 1)) s)")
            } catch {
                guard !Task.isCancelled else { return }
                registro.error("entrevista: tópicos falharam: \(error.localizedDescription, privacy: .private)")
                aviso = error.localizedDescription
            }
            pensando = false
        }
    }

    private func avisar(_ texto: String) {
        (aviso, pensando) = (texto, false)
        painel.mostrar()
    }
}

/// Painel transparente no canto da tela. Não pega o foco (o cursor continua na chamada) e pede para ficar fora de
/// gravações e do compartilhamento de tela (`sharingType = .none`).
@MainActor
final class PainelDaEntrevista {
    static let largura: CGFloat = 400
    private let janela: NSPanel

    init(modo: ModoEntrevista) {
        janela = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.largura, height: 200),
                         styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        janela.isFloatingPanel = true
        janela.level = .statusBar
        janela.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        janela.backgroundColor = .clear
        janela.isOpaque = false
        janela.hasShadow = false
        janela.hidesOnDeactivate = false
        janela.isMovableByWindowBackground = true
        janela.sharingType = .none
        let host = NSHostingView(rootView: PainelDaEntrevistaView(modo: modo))
        host.sizingOptions = [.preferredContentSize]
        janela.contentView = host
    }

    /// No canto de cima à direita da tela do mouse, longe da câmera e do rosto de quem está na chamada.
    func mostrar() {
        guard !janela.isVisible else { return }
        let mouse = NSEvent.mouseLocation
        let tela = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let area = tela?.visibleFrame else { return }
        janela.setFrameTopLeftPoint(NSPoint(x: area.maxX - Self.largura - 16, y: area.maxY - 16))
        janela.orderFrontRegardless()
    }

    func esconder() {
        janela.orderOut(nil)
    }
}

struct PainelDaEntrevistaView: View {
    let modo: ModoEntrevista

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(modo.pergunta ?? String(localized: "Modo entrevista"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Spacer()
                Button { modo.fechar() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Fechar")
            }
            if modo.pensando { ProgressView().controlSize(.small) }
            if let aviso = modo.aviso { Label(aviso, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            if let sugestao = modo.sugestao { TextoMarkdown(texto: sugestao) }
        }
        .padding(14)
        .frame(width: PainelDaEntrevista.largura, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .fixedSize(horizontal: false, vertical: true)
    }
}
