import AVFoundation
import AppKit
import Observation
import os

let registro = Logger(subsystem: "io.github.henriquebap.kanji", category: "ditado")

/// Fluxo do ditado em tempo real: a cada pausa, o trecho que o reconhecedor firmou é fundido (PT+EN),
/// revisado e só então escrito no campo em foco. Assim o campo nunca mostra texto "errado" para depois
/// corrigir; o painel mostra o que está sendo ouvido naquele instante.
@MainActor @Observable
final class Ditado {
    enum Fase: Equatable { case parado, preparando, gravando, ajustando, pronto(colado: Bool), erro(String) }

    static let barras = 36

    private(set) var fase: Fase = .parado
    private(set) var niveis = [Float](repeating: 0, count: barras)
    private(set) var revisado = ""   // texto já revisado, trecho a trecho: é o que vai para o campo
    private(set) var rascunho = ""   // o que está sendo ouvido agora e ainda não firmou (só no painel)
    private(set) var inicio = Date()
    private(set) var escrevendoEm: String?  // app onde o texto está sendo escrito ao vivo; nil = só no painel
    private(set) var revisandoCom: Provedor?  // revisão final do texto inteiro na nuvem em andamento
    private(set) var aviso: String?         // por que a revisão da nuvem não entrou (sem crédito, sem rede…)
    private(set) var aoVivo = true          // false: nada vai para o campo durante a fala, só o texto da nuvem no fim

    @ObservationIgnored private let historico: Historico
    @ObservationIgnored private let captura = CapturaAoVivo()
    @ObservationIgnored private lazy var painel = PainelFlutuante(ditado: self)
    @ObservationIgnored private var segurando = false
    @ObservationIgnored private var fechamento: Task<Void, Never>?
    @ObservationIgnored private var alvo: Alvo?
    @ObservationIgnored private var maiorNivel: Float = 0
    @ObservationIgnored private var revisao: RevisaoAoVivo?
    @ObservationIgnored private var fila: Task<Void, Never>?  // trechos são revisados um de cada vez, em ordem
    @ObservationIgnored private var brutos: [String] = []    // transcrição sem revisão, para o histórico
    @ObservationIgnored private var usarIngles = false
    @ObservationIgnored private var ultimaFala = Date.distantPast
    @ObservationIgnored private var falouDesdeQueFirmou = false
    @ObservationIgnored private var fimDoUltimoTrecho: Double?  // em segundos do áudio, para medir a pausa
    @ObservationIgnored private var defaults: UserDefaults { .standard }

    init(historico: Historico) {
        self.historico = historico
    }

    var ativo: Bool { fase == .preparando || fase == .gravando || fase == .ajustando }

    var icone: String {
        switch fase {
        case .parado, .pronto: "waveform"
        case .preparando, .gravando: "mic.fill"
        case .ajustando: "ellipsis.circle"
        case .erro: "exclamationmark.triangle"
        }
    }

    // MARK: - Atalho

    /// Modo alternar: cada toque liga/desliga. Modo segurar: grava enquanto a tecla está pressionada.
    func teclaDesceu() {
        registro.notice("atalho pressionado")
        segurando = true
        if defaults.bool(forKey: Ajustes.modoSegurar) {
            if !ativo { iniciar() }
        } else {
            alternar()
        }
    }

    func teclaSubiu() {
        segurando = false
        if defaults.bool(forKey: Ajustes.modoSegurar), fase == .gravando { parar() }
    }

    func alternar() {
        switch fase {
        case .gravando: parar()
        case .preparando, .ajustando: break
        case .parado, .pronto, .erro: iniciar()
        }
    }

    // MARK: - Fases

    func iniciar() {
        registro.notice("iniciar")
        fechamento?.cancel()
        (revisado, rascunho, brutos, niveis, maiorNivel) = ("", "", [], [Float](repeating: 0, count: Self.barras), 0)
        aviso = nil
        fila = nil
        fimDoUltimoTrecho = nil
        // Escrever só no fim depende de um modelo da nuvem; sem ele, o ditado continua escrevendo ao vivo.
        aoVivo = defaults.bool(forKey: Ajustes.escreverAoVivo) || Nuvem.pronto == nil
        revisao = novaRevisao()
        Correcao.aquecer()
        alvo = nil
        escrevendoEm = nil
        if defaults.bool(forKey: Ajustes.colarSozinho) {
            if aoVivo { mirarNoCampo() } else { escrevendoEm = NSWorkspace.shared.frontmostApplication?.localizedName }
        }
        fase = .preparando
        painel.mostrar()
        AtalhoGlobal.shared.registrar(.cancelar)
        Task {
            let primeiraVez = AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                return falhar(String(localized: "Sem acesso ao microfone. Libere em Ajustes do Sistema › Privacidade e Segurança › Microfone."))
            }
            // Logo depois de o macOS conceder o microfone, a primeira captura sai muda (visto nos testes).
            guard !primeiraVez else {
                return falhar(String(localized: "Microfone liberado. Aperte \(Acao.ditar.atalho.descricao) de novo para gravar."), som: .pronto)
            }
            registro.notice("microfone liberado")
            do {
                let idioma = defaults.string(forKey: Ajustes.idioma) ?? "pt_BR"
                usarIngles = defaults.bool(forKey: Ajustes.misturarIngles) && idioma.hasPrefix("pt")
                try await captura.iniciar(
                    idioma: idioma,
                    ingles: usarIngles,
                    aoNivel: { self.registrarNivel($0) },
                    aoTexto: { self.rascunho = $1 },
                    aoTrecho: { self.enfileirar($0, $1) })
                guard fase == .preparando else { return await captura.cancelar() }  // cancelado enquanto preparava
                registro.notice("gravando")
                fase = .gravando
                // Chrome monta a árvore de acessibilidade só depois do primeiro pedido: tenta achar o campo de novo.
                if aoVivo, alvo == nil, defaults.bool(forKey: Ajustes.colarSozinho) { mirarNoCampo() }
                inicio = .now
                Som.tocar(.inicio)
                // Modo segurar: a tecla pode ter sido solta enquanto o microfone ligava.
                if defaults.bool(forKey: Ajustes.modoSegurar), !segurando { parar() }
            } catch {
                falhar(String(localized: "Não consegui começar a gravar: \(error.localizedDescription)"))
            }
        }
    }

    func parar() {
        registro.notice("parar (fase: \(String(describing: self.fase), privacy: .public))")
        guard fase == .gravando else { return }
        fase = .ajustando
        Som.tocar(.fim)
        AtalhoGlobal.shared.desregistrar(.cancelar)
        Task {
            do {
                let resultado = try await captura.parar()  // os últimos trechos entram na fila durante a finalização
                await fila?.value
                rascunho = ""
                if revisado.isEmpty, !resultado.texto.isEmpty, let revisao {  // nenhum trecho firmou sozinho
                    brutos = [resultado.texto]
                    await revisao.processar(resultado.texto)
                    revisado = revisao.texto
                }
                guard !revisado.isEmpty else {
                    return falhar(maiorNivel < 0.15
                        ? String(localized: "O microfone não captou som. Confira a entrada em Ajustes do Sistema › Som.")
                        : String(localized: "Não entendi o que foi dito. Tente de novo, um pouco mais perto do microfone."), som: .vazio)
                }
                await revisarNaNuvem()
                guard fase == .ajustando else { return }  // cancelado enquanto a nuvem revisava
                historico.adicionar(.init(tipo: .ditado, texto: revisado, bruto: brutos.joined(separator: " "),
                                          app: NSWorkspace.shared.frontmostApplication?.localizedName))
                let colado = entregar(revisado)
                revisao = nil
                fase = .pronto(colado: colado)
                Som.tocar(.pronto)
                fecharPainel(em: colado && aviso == nil ? 1.2 : 4)  // o aviso precisa de tempo para ser lido
            } catch {
                falhar(String(localized: "Erro na transcrição: \(error.localizedDescription)"))
            }
        }
    }

    func cancelar() {
        registro.notice("cancelado")
        AtalhoGlobal.shared.desregistrar(.cancelar)
        if fase == .preparando || fase == .gravando {
            Task { await captura.cancelar() }
            _ = alvo?.atualizar(para: "")  // cancelar desfaz o que já foi escrito
        }
        pararFila()
        alvo = nil
        fase = .parado
        painel.esconder()
    }

    func copiarResultado() {
        Area.copiar(revisado, historico: historico)
        fecharPainel(em: 0.6)
    }

    // MARK: - Apoio

    /// Com um provedor da nuvem configurado, ele revisa o ditado inteiro a partir da transcrição crua e o campo
    /// recebe essa versão no lugar da revisão local. Sem chave, sem rede ou sem crédito, fica a local.
    /// Cada troca que ele faz alimenta o glossário que aprende (Aprendizado).
    private func revisarNaNuvem() async {
        guard let provedor = Nuvem.pronto else { return }
        revisandoCom = provedor
        defer { revisandoCom = nil }
        let bruto = brutos.joined(separator: " ")
        let estilo = defaults.string(forKey: Ajustes.instrucoes) ?? ""
        let (texto, falha) = await Nuvem.revisar(bruto, estilo: estilo, glossario: glossario)
        if let texto {
            revisado = texto
            Aprendizado.registrar(bruto: bruto, final: texto)
        }
        // No modo só no fim, o modelo do Mac não revisou os trechos: o que fica é a transcrição com as regras locais.
        aviso = falha.map {
            aoVivo ? String(localized: "Revisão na nuvem indisponível (\($0)). Ficou a revisão local.")
                   : String(localized: "Revisão na nuvem indisponível (\($0)). Ficou o texto transcrito.")
        }
    }

    /// O glossário dos Ajustes mais os termos que a revisão da nuvem já ensinou.
    private var glossario: [String] {
        let manual = (defaults.string(forKey: Ajustes.glossario) ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return manual + Aprendizado.termos.filter { termo in
            !manual.contains { $0.caseInsensitiveCompare(termo) == .orderedSame }
        }
    }

    private func registrarNivel(_ nivel: Float) {
        niveis = Array(niveis.dropFirst()) + [nivel]
        maiorNivel = max(maiorNivel, nivel)
        firmarNaPausa(nivel)
    }

    /// Pausa curta depois de fala: força o reconhecedor a fechar o trecho, que então é revisado e vai para o campo.
    /// Cortar em tempo fixo partia palavras ("Supa|base"); na pausa não há palavra pela metade.
    private func firmarNaPausa(_ nivel: Float) {
        guard fase == .gravando else { return }
        // ponytail: limiar relativo ao pico da voz; calibrar se ambientes barulhentos cortarem demais ou de menos
        let limiar = max(0.3, maiorNivel * 0.55)
        if nivel > limiar {
            ultimaFala = .now
            falouDesdeQueFirmou = true
        } else if falouDesdeQueFirmou, Date.now.timeIntervalSince(ultimaFala) > 0.35 {
            falouDesdeQueFirmou = false
            captura.firmar()
        }
    }

    private func novaRevisao() -> RevisaoAoVivo {
        let estilo = defaults.string(forKey: Ajustes.instrucoes) ?? ""
        let glossario = glossario
        // Só no fim, quem revisa é o Claude: o modelo local ficaria ocupado à toa durante a fala.
        let corrigir = defaults.bool(forKey: Ajustes.corrigir) && aoVivo
        return RevisaoAoVivo(glossario: glossario, comecaComNome: Fusao.comecaComNome) { trecho, anterior in
            corrigir ? await Correcao.revisarTrecho(trecho, anterior: anterior, estilo: estilo, glossario: glossario) : trecho
        }
    }

    /// Cada trecho firmado entra numa fila: funde com o inglês, revisa e escreve, sempre na ordem da fala.
    private func enfileirar(_ texto: String, _ palavras: [Palavra]) {
        var pausa: Double?
        if let fim = fimDoUltimoTrecho, let inicio = palavras.first?.inicio { pausa = inicio - fim }
        if let fim = palavras.last?.fim { fimDoUltimoTrecho = fim }
        let anterior = fila
        fila = Task {
            await anterior?.value
            let bruto = await fundir(texto, palavras)
            guard let revisao, !bruto.isEmpty else { return }
            brutos.append(bruto)
            await revisao.processar(bruto, pausa: pausa)
            revisado = revisao.texto
            escreverNoCampo()
        }
    }

    private func fundir(_ texto: String, _ palavras: [Palavra]) async -> String {
        let limpo = Fusao.aplicarGlossario(texto.trimmingCharacters(in: .whitespaces), glossario)
        return Fusao.semMaiusculaNoMeio(await comIngles(limpo, palavras), glossario: glossario)
    }

    private func comIngles(_ limpo: String, _ palavras: [Palavra]) async -> String {
        guard usarIngles, let inicio = palavras.first?.inicio, let fim = palavras.last?.fim else { return limpo }
        try? await Task.sleep(for: .milliseconds(150))  // o reconhecedor de inglês firma o mesmo trecho logo depois
        let ingles = captura.ingles(de: inicio, ate: fim)
        guard !ingles.isEmpty else { return limpo }
        let fundido = Fusao.aplicarGlossario(Fusao.fundir(pt: palavras, en: ingles, glossario: glossario), glossario)
        if fundido != limpo { registro.notice("fusão PT+EN ajustou um trecho") }
        return fundido
    }

    /// O campo recebe só texto revisado. Se recusar logo de cara, o ditado segue pelo painel.
    private func escreverNoCampo() {
        guard aoVivo, let alvo, !alvo.atualizar(para: revisado), alvo.escrito.isEmpty else { return }
        registro.notice("campo recusou a escrita ao vivo; seguindo pelo painel")
        self.alvo = nil
        escrevendoEm = nil
    }

    private func mirarNoCampo() {
        alvo = Alvo.emFoco()
        escrevendoEm = alvo.map { $0.app ?? String(localized: "campo selecionado") }
    }

    private func pararFila() {
        fila?.cancel()
        fila = nil
        revisao = nil
    }

    /// Põe o texto final no lugar: troca o que foi escrito ao vivo ou cola.
    /// Sem nada escrito ao vivo (modo só no fim), cola com ⌘V, que funciona em qualquer app: no app do Claude
    /// a escrita por Acessibilidade respondia "ok" e não escrevia nada.
    private func entregar(_ texto: String) -> Bool {
        defer { alvo = nil }
        if let alvo, !alvo.escrito.isEmpty {
            if alvo.atualizar(para: texto) { return true }
            // O campo mudou no meio (clique em outro lugar): o rascunho fica e a versão ajustada vai para o clipboard.
            Area.copiar(texto, historico: historico)
            return false
        }
        return Area.colar(texto, sozinho: defaults.bool(forKey: Ajustes.colarSozinho), historico: historico)
    }

    private func falhar(_ mensagem: String, som: Som = .erro) {
        registro.error("\(mensagem, privacy: .public)")
        AtalhoGlobal.shared.desregistrar(.cancelar)
        Task { await captura.cancelar() }
        pararFila()
        fase = .erro(mensagem)
        Som.tocar(som)
        fecharPainel(em: 4)
    }

    private func fecharPainel(em segundos: Double) {
        fechamento?.cancel()
        fechamento = Task {
            try? await Task.sleep(for: .seconds(segundos))
            guard !Task.isCancelled else { return }
            painel.esconder()
            fase = .parado
        }
    }
}
