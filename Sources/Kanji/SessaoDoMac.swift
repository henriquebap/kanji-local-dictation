import AppKit
import Observation

/// Transcrição longa do que o Mac está tocando (vídeo, podcast, reunião), salva trecho a trecho em
/// Application Support/Kanji/Transcricoes: se o app cair no meio, o que já firmou continua no disco.
@MainActor @Observable
final class SessaoDoMac {
    enum Fase: Equatable { case parada, preparando, gravando, finalizando, erro(String) }

    static let pasta = URL.applicationSupportDirectory.appending(path: "Kanji/Transcricoes")

    private(set) var fase: Fase = .parada
    private(set) var inicio = Date()
    private(set) var trechos = 0

    @ObservationIgnored private let captura = CapturaAoVivo()
    @ObservationIgnored private var transcricao: Transcricao?
    @ObservationIgnored private var fila: Task<Void, Never>?  // trechos entram um de cada vez, em ordem
    @ObservationIgnored private var soIngles: [(texto: String, palavras: [Palavra])] = []  // esperando o português
    @ObservationIgnored private var firmouAte: Double = 0  // fim do último trecho em português, em segundos do áudio
    @ObservationIgnored private var maiorNivel: Float = 0

    var ativa: Bool { fase == .preparando || fase == .gravando || fase == .finalizando }

    func alternar() {
        switch fase {
        case .gravando: parar()
        case .preparando, .finalizando: break
        case .parada, .erro: iniciar()
        }
    }

    func iniciar() {
        guard !ativa else { return }
        fase = .preparando
        (inicio, trechos, maiorNivel, fila, soIngles, firmouAte) = (.now, 0, 0, nil, [], 0)
        transcricao = Transcricao(inicio: inicio)
        Task {
            do {
                let idioma = UserDefaults.standard.string(forKey: Ajustes.idioma) ?? "pt_BR"
                try await captura.iniciar(
                    idioma: idioma,
                    ingles: UserDefaults.standard.bool(forKey: Ajustes.misturarIngles) && idioma.hasPrefix("pt"),
                    origem: .mac,
                    aoNivel: { self.maiorNivel = max(self.maiorNivel, $0) },
                    aoTexto: { _, _ in },
                    aoTrecho: { self.enfileirar($0, $1) },
                    aoTrechoIngles: { self.soEmIngles($0, $1) })
                fase = .gravando
                registro.notice("sessão do Mac gravando")
                Som.tocar(.inicio)  // o tap exclui o Kanji: o som não entra na transcrição
            } catch {
                await captura.cancelar()
                falhar(String(localized: "Não consegui ouvir o áudio do Mac: \(error.localizedDescription)"))
            }
        }
    }

    func parar() {
        guard fase == .gravando else { return }
        fase = .finalizando
        Task {
            let resultado = try? await captura.parar()  // os últimos trechos entram na fila durante a finalização
            await fila?.value
            resolverIngles(ate: .infinity)
            // Nada firmou sozinho (fala curta, sem pausa): fica o texto inteiro como um trecho.
            if trechos == 0, let resultado, !resultado.texto.isEmpty {
                adicionar(resultado.texto, resultado.principal)
            }
            transcricao?.fim = .now
            salvar()
            registro.notice("sessão do Mac: \(self.trechos) trechos em \(Int(Date.now.timeIntervalSince(self.inicio))) s, pico \(self.maiorNivel, privacy: .public)")
            Som.tocar(.pronto)
            guard trechos > 0 else {
                // Sem a permissão, o tap entrega silêncio sem dar erro: o nível nunca sobe.
                return falhar(maiorNivel < 0.05
                    ? String(localized: "Nenhum som do Mac chegou. Libere o Kanji em Ajustes do Sistema › Privacidade e Segurança › Gravação de Áudio do Sistema.")
                    : String(localized: "Ouvi o áudio do Mac, mas não reconheci fala."))
            }
            fase = .parada
        }
    }

    func abrirPasta() {
        try? FileManager.default.createDirectory(at: Self.pasta, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Self.pasta)
    }

    // MARK: - Apoio

    // Diferente do ditado, a sessão não força o fim do trecho na pausa: `finalize` seguido de silêncio digital
    // (o tap entrega zeros entre uma fala e outra) faz os resultados terminarem com RecogRejected, e nada mais
    // era transcrito depois disso (reproduzido com `say`). O reconhecedor fecha os trechos sozinho; demora mais,
    // e num arquivo isso não importa.

    private func enfileirar(_ texto: String, _ palavras: [Palavra]) {
        let anterior = fila
        fila = Task {
            await anterior?.value
            adicionar(await captura.textoFinal(texto, palavras, glossario: Ditado.glossario), palavras)
            firmouAte = max(firmouAte, palavras.last?.fim ?? 0)
            resolverIngles(ate: firmouAte)
            salvar()
        }
    }

    /// O reconhecedor de português não firma nada para uma fala toda em inglês: a frase sumia (testado com `say`).
    /// O de inglês, por outro lado, devolve lixo para fala em português ("You don't pretty see the German", uma
    /// fileira de vírgulas, visto num podcast). Por isso o trecho em inglês espera o português firmar além do fim
    /// dele, o que leva de 30 s a 1 min sem forçar o fim do trecho, e só entra se nada em português cobriu o mesmo tempo.
    private func soEmIngles(_ texto: String, _ palavras: [Palavra]) {
        guard !palavras.isEmpty, texto.contains(where: \.isLetter) else { return }
        soIngles.append((texto, palavras))
    }

    // ponytail: um trecho em inglês que encosta num de português fica de fora; separar por palavra se aparecer no uso.
    private func resolverIngles(ate limite: Double) {
        let prontos = soIngles.filter { ($0.palavras.last?.fim ?? 0) <= limite }
        soIngles = soIngles.filter { ($0.palavras.last?.fim ?? 0) > limite }
        for (texto, palavras) in prontos {
            let (inicio, fim) = (palavras.first?.inicio ?? 0, palavras.last?.fim ?? 0)
            guard transcricao?.trechos.contains(where: { $0.fim > inicio && $0.inicio < fim }) == false else { continue }
            adicionar(Fusao.aplicarGlossario(texto.trimmingCharacters(in: .whitespaces), Ditado.glossario), palavras)
        }
    }

    private func adicionar(_ texto: String, _ palavras: [Palavra]) {
        // O reconhecedor às vezes abre o trecho com a pontuação do anterior (". o desenho que eu fiz…", num podcast).
        let texto = String(texto.drop { $0.isPunctuation || $0.isWhitespace })
        guard !texto.isEmpty else { return }
        let inicio = palavras.first?.inicio ?? 0
        transcricao?.adicionar(Trecho(inicio: inicio, fim: palavras.last?.fim ?? inicio, canal: .mac, texto: texto))
        trechos += 1
    }

    /// ponytail: reescreve os dois arquivos inteiros a cada trecho; numa sessão de horas são poucos MB.
    /// Anexar (JSON Lines) se o tempo de escrita aparecer no perfil.
    private func salvar() {
        guard let transcricao, !transcricao.trechos.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: Self.pasta, withIntermediateDirectories: true)
            let base = Self.pasta.appending(path: transcricao.nomeDoArquivo)
            let codificador = JSONEncoder()
            codificador.dateEncodingStrategy = .iso8601
            codificador.outputFormatting = [.prettyPrinted, .sortedKeys]
            try codificador.encode(transcricao).write(to: base.appendingPathExtension("json"), options: .atomic)
            try Data(transcricao.markdown().utf8).write(to: base.appendingPathExtension("md"), options: .atomic)
        } catch {
            registro.error("falha ao salvar a transcrição: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func falhar(_ mensagem: String) {
        registro.error("\(mensagem, privacy: .public)")
        fase = .erro(mensagem)
        Som.tocar(.erro)
    }
}
