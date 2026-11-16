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
    @ObservationIgnored private let microfone = CanalDoMicrofone()
    @ObservationIgnored private var transcricao: Transcricao?
    @ObservationIgnored private var fila: Task<Void, Never>?  // trechos entram um de cada vez, em ordem
    @ObservationIgnored private var soIngles: [(texto: String, palavras: [Palavra])] = []  // esperando o português
    @ObservationIgnored private var firmouAte: Double = 0  // fim do último trecho em português, em segundos do áudio
    @ObservationIgnored private var maiorNivel: Float = 0
    // Separação de locutores, só com o modelo baixado e a opção ligada nos Ajustes.
    @ObservationIgnored private var voz: ImpressaoDeVoz?
    @ObservationIgnored private var memoria: MemoriaDeAudio?
    @ObservationIgnored private var locutores = Locutores(limiar: SessaoDoMac.limiar)
    @ObservationIgnored private var numeros: [Int: Int] = [:]  // grupo → número no arquivo, na ordem em que aparece
    @ObservationIgnored private var ultimoGrupo: Int?  // quem falava por último, para a janela que ficou sem áudio

    // ponytail: limiar fixo, calibrado num podcast; virar ajuste se variar muito entre gravações.
    static let limiar: Float = 0.5

    var ativa: Bool { fase == .preparando || fase == .gravando || fase == .finalizando }

    func alternar() {
        switch fase {
        case .gravando: parar()
        case .preparando, .finalizando: break
        case .parada, .erro: if Self.consentiu() { iniciar() }
        }
    }

    func iniciar() {
        guard !ativa else { return }
        fase = .preparando
        (inicio, trechos, maiorNivel, fila, soIngles, firmouAte) = (.now, 0, 0, nil, [], 0)
        transcricao = Transcricao(inicio: inicio)
        (voz, memoria, locutores, numeros, ultimoGrupo) = (nil, nil, Locutores(limiar: Self.limiar), [:], nil)
        Task {
            do {
                if UserDefaults.standard.bool(forKey: Ajustes.separarLocutores) {
                    if ModeloDeVozes.shared.estado == .pronto {
                        do {
                            voz = try await Task.detached {
                                try ModeloDeVozes.conferir()  // um arquivo trocado depois do download não é carregado
                                return try ImpressaoDeVoz(pasta: ModeloDeVozes.pasta)
                            }.value
                            memoria = MemoriaDeAudio()
                        } catch {
                            // Sem o modelo a sessão segue, só sem separar quem fala.
                            registro.error("modelo de locutores não carregou: \(error.localizedDescription, privacy: .public)")
                            ModeloDeVozes.shared.descartar()
                        }
                    } else {
                        registro.notice("separação de locutores ligada, mas o modelo não está pronto; sessão sem locutores")
                    }
                }
                let idioma = UserDefaults.standard.string(forKey: Ajustes.idioma) ?? "pt_BR"
                try await captura.iniciar(
                    idioma: idioma,
                    ingles: UserDefaults.standard.bool(forKey: Ajustes.misturarIngles) && idioma.hasPrefix("pt"),
                    origem: .mac,
                    aoNivel: { self.maiorNivel = max(self.maiorNivel, $0) },
                    aoTexto: { _, _ in },
                    aoTrecho: { self.enfileirar($0, $1) },
                    aoTrechoIngles: { self.soEmIngles($0, $1) },
                    memoria: memoria)
                fase = .gravando
                mostrarNaIlha(chamada: false)
                microfone.vigiar(desde: .now, aoMudar: { self.mostrarNaIlha(chamada: $0) }) { texto, palavras in
                    self.enfileirarDoMicrofone(texto, palavras)
                }
                registro.notice("sessão do Mac gravando\(self.voz == nil ? "" : ", separando locutores", privacy: .public)")
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
            await microfone.parar()
            try? await Task.sleep(for: .milliseconds(300))  // a fusão dos últimos trechos do microfone espera 150 ms
            await fila?.value
            await resolverIngles(ate: .infinity)
            // Nada firmou sozinho (fala curta, sem pausa): fica o texto inteiro como um trecho.
            if trechos == 0, let resultado, !resultado.texto.isEmpty {
                await registrar(resultado.texto, resultado.principal, fundir: false)
            }
            transcricao?.fim = .now
            salvar()
            (voz, memoria) = (nil, nil)  // o modelo e os 3 min de áudio só ocupam memória durante a sessão
            registro.notice("sessão do Mac: \(self.trechos) trechos em \(Int(Date.now.timeIntervalSince(self.inicio))) s, pico \(self.maiorNivel, privacy: .public)")
            Som.tocar(.pronto)
            guard trechos > 0 else {
                // Sem a permissão, o tap entrega silêncio sem dar erro: o nível nunca sobe.
                return falhar(maiorNivel < 0.05
                    ? String(localized: "Nenhum som do Mac chegou. Libere o Kanji em Ajustes do Sistema › Privacidade e Segurança › Gravação de Áudio do Sistema.")
                    : String(localized: "Ouvi o áudio do Mac, mas não reconheci fala."))
            }
            Ilha.mostrar(String(localized: "Transcrição salva"),
                         detalhe: String(localized: "\(String(trechos)) trechos em \(String(max(1, Int(Date.now.timeIntervalSince(inicio) / 60)))) min"),
                         simbolo: "checkmark.circle.fill", cor: "verde", expira: 8)
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
            await registrar(texto, palavras, fundir: true)
            firmouAte = max(firmouAte, palavras.last?.fim ?? 0)
            await resolverIngles(ate: firmouAte)
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
    private func resolverIngles(ate limite: Double) async {
        let prontos = soIngles.filter { ($0.palavras.last?.fim ?? 0) <= limite }
        soIngles = soIngles.filter { ($0.palavras.last?.fim ?? 0) > limite }
        for (texto, palavras) in prontos {
            let (inicio, fim) = (palavras.first?.inicio ?? 0, palavras.last?.fim ?? 0)
            guard transcricao?.trechos.contains(where: { $0.canal == .mac && $0.fim > inicio && $0.inicio < fim }) == false
            else { continue }
            await registrar(texto, palavras, fundir: false)
        }
    }

    /// Com a separação ligada, o trecho se divide onde a voz muda e cada parte entra com o seu locutor.
    /// - fundir: passa pela fusão PT+EN (trecho do reconhecedor de português) ou só pelo glossário (inglês sozinho).
    private func registrar(_ texto: String, _ palavras: [Palavra], fundir: Bool) async {
        let partes = await porLocutor(palavras)
        guard partes.count > 1 else {
            return adicionar(await final(texto, palavras, fundir), palavras, locutor: partes.first?.locutor)
        }
        for parte in partes {
            adicionar(await final(parte.palavras.map(\.texto).joined(), parte.palavras, fundir), parte.palavras,
                      locutor: parte.locutor)
        }
    }

    private func final(_ texto: String, _ palavras: [Palavra], _ fundir: Bool) async -> String {
        fundir ? await captura.textoFinal(texto, palavras, glossario: Ditado.glossario)
               : Fusao.aplicarGlossario(texto.trimmingCharacters(in: .whitespaces), Ditado.glossario)
    }

    /// Partes seguidas do mesmo locutor. Vazio quando não há separação (sem modelo, ou o áudio já saiu da memória).
    private func porLocutor(_ palavras: [Palavra]) async -> [(locutor: Int, palavras: [Palavra])] {
        guard let voz, let memoria, !palavras.isEmpty else { return [] }
        let janelas = Locutores.janelas(palavras)
        let intervalos = janelas.map { (palavras[$0.lowerBound].inicio, palavras[$0.upperBound - 1].fim) }
        // Cada janela vai ao modelo dentro de 10 s de áudio de verdade em volta, marcada pela máscara. Com a janela
        // sozinha e zeros completando os 10 s, duas vozes diferentes davam 0,65–0,80 de semelhança; com contexto,
        // 0,01–0,20 (medido com o áudio gravado pelo próprio tap).
        let fim = memoria.duracao
        let pedidos = intervalos.map { (a, b) -> (audio: [Float]?, intervalo: (Double, Double)) in
            let inicio = max(0, min((a + b) / 2 - 5, fim - 10))
            return (memoria.audio(de: inicio, ate: inicio + 10), (a - inicio, min(b, a + 10) - inicio))
        }
        let vetores: [[Float]?] = await Task.detached {
            pedidos.map { pedido in
                pedido.audio.flatMap { try? voz.vetores(audio: $0[...], intervalos: [pedido.intervalo]).first }
            }
        }.value
        guard vetores.contains(where: { $0 != nil }) else { return [] }
        let grupos = zip(vetores, intervalos).map { vetor, intervalo -> Int? in
            guard let vetor else { return ultimoGrupo }  // sem áudio: fica com quem falava antes
            let semelhanca = locutores.centros.map { Locutores.cosseno($0, vetor) }.max() ?? 0
            let grupo = locutores.identificar(vetor, confiavel: intervalo.1 - intervalo.0 >= 1)
            ultimoGrupo = grupo
            registro.debug("janela: semelhança \(semelhanca, format: .fixed(precision: 2), privacy: .public) → grupo \(grupo, privacy: .public)")
            return grupo
        }
        // Janelas sem áudio no começo da sessão ficam com o primeiro locutor que aparecer no trecho.
        guard let primeiro = grupos.first(where: { $0 != nil }) ?? nil else { return [] }
        let preenchidos = grupos.map { $0 ?? primeiro }
        let suavizados = Locutores.suavizar(preenchidos, duracoes: intervalos.map { $0.1 - $0.0 })
        var partes: [(locutor: Int, palavras: [Palavra])] = []
        for (janela, grupo) in zip(janelas, suavizados) {
            let numero = numeros[grupo] ?? (numeros.count + 1)
            numeros[grupo] = numero
            if partes.last?.locutor == numero {
                partes[partes.count - 1].palavras += palavras[janela]
            } else {
                partes.append((numero, Array(palavras[janela])))
            }
        }
        return partes
    }

    /// O que o microfone ouviu numa chamada: entra como "Você", sem separar vozes.
    private func enfileirarDoMicrofone(_ texto: String, _ palavras: [Palavra]) {
        let anterior = fila
        fila = Task {
            await anterior?.value
            adicionar(texto, palavras, canal: .microfone)
            salvar()
        }
    }

    private func adicionar(_ texto: String, _ palavras: [Palavra], locutor: Int? = nil, canal: Trecho.Canal = .mac) {
        // O reconhecedor às vezes abre o trecho com a pontuação do anterior (". o desenho que eu fiz…", num podcast).
        let texto = String(texto.drop { $0.isPunctuation || $0.isWhitespace })
        guard !texto.isEmpty else { return }
        let inicio = palavras.first?.inicio ?? 0
        transcricao?.adicionar(Trecho(inicio: inicio, fim: palavras.last?.fim ?? inicio, canal: canal,
                                      locutor: locutor.map { "Locutor \($0)" }, texto: texto))
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
        Ilha.mostrar(String(localized: "A transcrição do Mac parou"), detalhe: mensagem,
                     simbolo: "exclamationmark.triangle.fill", cor: "laranja", expira: 15)
    }

    /// Fica na ilha do Kizami enquanto grava. Uma chamada aparece à parte porque aí a sua voz também entra.
    private func mostrarNaIlha(chamada: Bool) {
        guard fase == .gravando else { return }  // o microfone desliga ao parar: não volta a dizer "transcrevendo"
        Ilha.mostrar(String(localized: "Transcrevendo o áudio do Mac"),
                     detalhe: chamada ? String(localized: "Numa chamada: o seu microfone também entra") : nil,
                     simbolo: chamada ? "mic.fill" : "waveform", cor: "vermelho")
    }

    /// Na primeira vez, lembra que transcrever uma reunião pede o consentimento de quem está nela.
    private static func consentiu() -> Bool {
        guard !UserDefaults.standard.bool(forKey: Ajustes.viuAvisoDeGravacao) else { return true }
        let alerta = NSAlert()
        alerta.messageText = String(localized: "Antes de transcrever o áudio do Mac")
        alerta.informativeText = String(localized: "O Kanji vai transcrever tudo o que o Mac tocar. Numa chamada, o seu microfone também entra, como “Você”. Avise as pessoas antes de transcrever uma reunião: gravar uma conversa sem consentimento pode ferir a LGPD e as regras da sua empresa.\n\nO áudio não sai do Mac. O texto fica em Application Support › Kanji › Transcricoes.")
        alerta.addButton(withTitle: String(localized: "Transcrever"))
        alerta.addButton(withTitle: String(localized: "Cancelar"))
        NSApp.activate()  // pelo atalho global o Kanji não está na frente, e o alerta ficaria atrás
        guard alerta.runModal() == .alertFirstButtonReturn else { return false }
        UserDefaults.standard.set(true, forKey: Ajustes.viuAvisoDeGravacao)
        return true
    }
}
