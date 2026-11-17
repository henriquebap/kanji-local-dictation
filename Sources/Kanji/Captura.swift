import Accelerate
import AVFoundation
import Speech

/// Microfone ou áudio do Mac → SpeechAnalyzer ao vivo. Entrega o nível do áudio e o texto parcial enquanto grava.
@MainActor
final class CapturaAoVivo {
    enum Origem { case microfone, mac }

    private var engine: AVAudioEngine?  // criado a cada gravação: um engine criado antes da permissão do microfone grava silêncio
    private var mac: AudioDoMac?
    private(set) var comIngles = false
    private var analyzer: SpeechAnalyzer?
    private var entrada: AsyncStream<AnalyzerInput>.Continuation?
    private var leituras: [Task<Void, Never>] = []
    private var firmado = ""
    private var rascunho = ""
    private var palavrasPrincipal: [Palavra] = []
    private var palavrasIngles: [Palavra] = []

    /// O que saiu de uma gravação: o texto do idioma principal e as palavras com tempo de cada reconhecedor.
    struct Resultado {
        let texto: String
        let principal: [Palavra]
        let ingles: [Palavra]
    }

    /// - ingles: roda também um reconhecedor de inglês no mesmo áudio, para a fusão de termos.
    /// - aoNivel: 0…1, várias vezes por segundo (para a onda).
    /// - aoTexto: (texto já firmado, rascunho que ainda pode mudar), do idioma principal.
    /// - aoTrecho: cada trecho que o reconhecedor firma (em geral a cada pausa), com as palavras e seus tempos.
    /// - semEco: cancelamento de eco do microfone (voice processing), para a caixa de som não entrar como fala.
    func iniciar(idioma: String, ingles: Bool, origem: Origem = .microfone, semEco: Bool = false,
                 aoNivel: @escaping @MainActor (Float) -> Void,
                 aoTexto: @escaping @MainActor (String, String) -> Void,
                 aoTrecho: @escaping @MainActor (String, [Palavra]) -> Void,
                 aoTrechoIngles: (@MainActor (String, [Palavra]) -> Void)? = nil,
                 memoria: MemoriaDeAudio? = nil) async throws {
        let atributos: Set<SpeechTranscriber.ResultAttributeOption> = [.audioTimeRange, .transcriptionConfidence]
        let principal = SpeechTranscriber(locale: Locale(identifier: idioma), transcriptionOptions: [],
                                          reportingOptions: [.volatileResults, .fastResults], attributeOptions: atributos)
        let segundo = ingles
            ? SpeechTranscriber(locale: Locale(identifier: "en_US"), transcriptionOptions: [], reportingOptions: [.fastResults],
                                attributeOptions: atributos)
            : nil
        // Detector de voz: o reconhecedor só olha o áudio com fala. Sem ele, o silêncio e o ruído de fundo
        // viravam palavras que ninguém disse ("é isso aí" + silêncio → "E é isso. Não.").
        let detector = SpeechDetector(detectionOptions: .init(sensitivityLevel: .medium), reportResults: false)
        let modulos: [any SpeechModule] = [detector, principal] + (segundo.map { [$0] } ?? [])
        if let pedido = try await AssetInventory.assetInstallationRequest(supporting: modulos) {
            try await pedido.downloadAndInstall()
        }
        registro.notice("modelos de fala prontos (\(modulos.count - 1, privacy: .public) idiomas)")
        let conversor = try await AnalyzerInputConverter.converter(compatibleWith: modulos)
        let analyzer = SpeechAnalyzer(modules: modulos)
        let (fluxo, entrada) = AsyncStream.makeStream(of: AnalyzerInput.self)
        try await analyzer.start(inputSequence: fluxo)

        (firmado, rascunho, palavrasPrincipal, palavrasIngles) = ("", "", [], [])
        comIngles = ingles
        leituras = [Task {
            do {
                for try await r in principal.results {
                    let texto = String(r.text.characters)
                    if r.isFinal {
                        firmado += texto
                        let palavras = Palavra.de(r)
                        palavrasPrincipal += palavras
                        aoTrecho(texto, palavras)
                    }
                    rascunho = r.isFinal ? "" : texto
                    aoTexto(firmado, rascunho)
                }
            } catch {
                registro.error("leitura da transcrição: \(error, privacy: .public)")
            }
        }]
        if let segundo {
            leituras.append(Task {
                do {
                    for try await r in segundo.results where r.isFinal {
                        let palavras = Palavra.de(r)
                        palavrasIngles += palavras
                        aoTrechoIngles?(String(r.text.characters), palavras)
                    }
                } catch {
                    registro.error("leitura em inglês: \(error, privacy: .public)")
                }
            })
        }

        self.analyzer = analyzer
        self.entrada = entrada
        let receber = Self.receptor(conversor: conversor, entrada: entrada, memoria: memoria) { n in Task { @MainActor in aoNivel(n) } }
        switch origem {
        case .microfone:
            // ponytail: installTap foi deprecado no 27, mas a versão nova (com error:) ainda não tem refinamento em Swift
            let engine = AVAudioEngine()
            let mic = engine.inputNode
            if semEco {
                try mic.setVoiceProcessingEnabled(true)
                // Por padrão o voice processing abaixa o som dos outros apps, e a chamada ficaria baixa.
                mic.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
            }
            mic.installTap(onBus: 0, bufferSize: 1024, format: mic.outputFormat(forBus: 0), block: Self.blocoDoMicrofone(receber))
            engine.prepare()
            self.engine = engine
            try engine.start()
        case .mac:
            let mac = AudioDoMac()
            self.mac = mac
            try mac.iniciar(aoBuffer: receber)
        }
    }

    /// Para o microfone, espera os modelos firmarem o fim da fala e devolve o que foi reconhecido.
    func parar() async throws -> Resultado {
        desligarFonte()
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch let erro as NSError where erro.domain == "SFSpeechErrorDomain" && erro.code == 1 {
            // "RecogRejected": com o detector de voz, um trecho já firmado na pausa seguido só de silêncio até o fim
            // faz o finalizar falhar (reproduzido com áudio sintetizado). O texto já firmado continua valendo.
            registro.notice("fim só com silêncio (RecogRejected); fica o que já firmou")
        } catch {
            // Outro erro também não pode levar o texto já firmado nem deixar as leituras vivas para a próxima gravação.
            registro.error("finalizar falhou: \(error.localizedDescription, privacy: .public); fica o que já firmou")
        }
        // `results` não termina sozinho após finalizar: dá um instante para os últimos resultados
        // chegarem e encerra a leitura. Rascunho que sobrou entra também, para não perder palavras.
        try? await Task.sleep(for: .milliseconds(250))
        leituras.forEach { $0.cancel() }
        leituras = []
        analyzer = nil
        let texto = (firmado + rascunho).trimmingCharacters(in: .whitespacesAndNewlines)
        registro.notice("finalizado: \(texto.count) caracteres, \(self.palavrasIngles.count) palavras em inglês")
        return Resultado(texto: texto, principal: palavrasPrincipal, ingles: palavrasIngles)
    }

    /// Fecha o trecho em andamento agora. Sem isso, falando sem pausa marcada, o reconhecedor segura o texto
    /// por 10 s ou mais (medido: uma frase de 14 s saiu num trecho só). Chamado nas pausas curtas da fala.
    func firmar() {
        guard let analyzer else { return }
        Task { try? await analyzer.finalize(through: nil) }
    }

    /// O texto de um trecho firmado com o glossário, a fusão PT+EN e sem maiúscula no meio da frase.
    func textoFinal(_ texto: String, _ palavras: [Palavra], glossario: [String]) async -> String {
        let limpo = Fusao.aplicarGlossario(texto.trimmingCharacters(in: .whitespaces), glossario)
        return Fusao.semMaiusculaNoMeio(await fundidoComIngles(limpo, palavras, glossario), glossario: glossario)
    }

    private func fundidoComIngles(_ limpo: String, _ palavras: [Palavra], _ glossario: [String]) async -> String {
        guard comIngles, let inicio = palavras.first?.inicio, let fim = palavras.last?.fim else { return limpo }
        try? await Task.sleep(for: .milliseconds(150))  // o reconhecedor de inglês firma o mesmo trecho logo depois
        // ponytail: filtro linear sobre todas as palavras da sessão; numa sessão de horas são dezenas de milhares,
        // ainda barato. Descartar as palavras antigas se aparecer no perfil.
        let ingles = palavrasIngles.filter { $0.fim > inicio && $0.inicio < fim }
        guard !ingles.isEmpty else { return limpo }
        let fundido = Fusao.aplicarGlossario(Fusao.fundir(pt: palavras, en: ingles, glossario: glossario), glossario)
        if fundido != limpo { registro.notice("fusão PT+EN ajustou um trecho") }
        return fundido
    }

    func cancelar() async {
        desligarFonte()
        leituras.forEach { $0.cancel() }
        leituras = []
        await analyzer?.cancelAndFinishNow()
        analyzer = nil
    }

    private func desligarFonte() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        mac?.parar()
        mac = nil
        entrada?.finish()
        entrada = nil
    }

    /// O bloco roda na thread de áudio. Fica `nonisolated` para o Swift 6 não herdar o MainActor
    /// (o que derruba o app com assert de isolamento na primeira chamada).
    nonisolated private static func receptor(conversor: AnalyzerInputConverter,
                                             entrada: AsyncStream<AnalyzerInput>.Continuation,
                                             memoria: MemoriaDeAudio?,
                                             aoNivel: @escaping @Sendable (Float) -> Void) -> @Sendable (AVAudioPCMBuffer) -> Void {
        // Tudo abaixo é usado só pela thread de áudio da origem.
        nonisolated(unsafe) let conversor = conversor
        nonisolated(unsafe) var formatoInicial: AVAudioFormat?
        nonisolated(unsafe) var normalizador: AVAudioConverter?
        nonisolated(unsafe) var paraMemoria: AVAudioConverter?
        let formatoDaMemoria = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: ImpressaoDeVoz.taxa,
                                             channels: 1, interleaved: false)
        return { buffer in
            aoNivel(nivel(buffer))
            // O conversor do reconhecedor fica preso ao formato do primeiro buffer: quando a saída mudou de 48 para
            // 24 kHz numa chamada, ele não devolveu nada nem deu erro, e a fala da chamada sumia. Todo buffer chega
            // a ele no formato inicial.
            let inicial = formatoInicial ?? buffer.format
            formatoInicial = inicial
            if let pronto = buffer.format == inicial ? buffer : reamostrar(buffer, para: inicial, conversor: &normalizador) {
                do {
                    for pedaco in try conversor.convert(pronto, at: nil) { entrada.yield(pedaco) }
                } catch {
                    registro.error("conversão de áudio falhou: \(error, privacy: .public)")
                }
            }
            if let memoria, let formatoDaMemoria,
               let copia = reamostrar(buffer, para: formatoDaMemoria, conversor: &paraMemoria),
               let dados = copia.floatChannelData {
                memoria.anexar(UnsafeBufferPointer(start: dados[0], count: Int(copia.frameLength)))
            }
        }
    }

    /// Um bloco escrito dentro de `iniciar` herda o MainActor e derruba o app na primeira chamada, na thread de áudio
    /// (crash visto ao ligar o microfone da sessão): por isso ele nasce aqui, fora do ator.
    nonisolated private static func blocoDoMicrofone(_ receber: @escaping @Sendable (AVAudioPCMBuffer) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in receber(buffer) }
    }

    /// Reamostra um buffer. O conversor guarda estado entre os buffers, então a reamostragem é contínua e o tempo de
    /// cada amostra continua batendo com o do reconhecedor; ele é refeito quando o formato de entrada muda.
    nonisolated private static func reamostrar(_ buffer: AVAudioPCMBuffer, para formato: AVAudioFormat,
                                              conversor: inout AVAudioConverter?) -> AVAudioPCMBuffer? {
        if conversor?.inputFormat != buffer.format { conversor = AVAudioConverter(from: buffer.format, to: formato) }
        let capacidade = AVAudioFrameCount(Double(buffer.frameLength) * formato.sampleRate / buffer.format.sampleRate) + 64
        guard let conversor, let saida = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: capacidade) else { return nil }
        nonisolated(unsafe) var entregue = false
        var erro: NSError?
        conversor.convert(to: saida, error: &erro) { _, status in
            if entregue { status.pointee = .noDataNow; return nil }
            entregue = true
            status.pointee = .haveData
            return buffer
        }
        return erro == nil ? saida : nil
    }

    /// RMS em dB mapeado para 0…1 (−50 dB = silêncio, 0 dB = máximo).
    nonisolated private static func nivel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let amostras = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var rms: Float = 0
        vDSP_rmsqv(amostras, 1, &rms, vDSP_Length(buffer.frameLength))
        return min(1, max(0, (20 * log10(max(rms, 1e-6)) + 50) / 50))
    }
}
