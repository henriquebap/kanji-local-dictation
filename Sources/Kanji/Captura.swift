import Accelerate
import AVFoundation
import Speech

/// Microfone → SpeechAnalyzer ao vivo. Entrega o nível do áudio e o texto parcial enquanto grava.
@MainActor
final class CapturaAoVivo {
    private var engine: AVAudioEngine?  // criado a cada gravação: um engine criado antes da permissão do microfone grava silêncio
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
    func iniciar(idioma: String, ingles: Bool,
                 aoNivel: @escaping @MainActor (Float) -> Void,
                 aoTexto: @escaping @MainActor (String, String) -> Void,
                 aoTrecho: @escaping @MainActor (String, [Palavra]) -> Void) async throws {
        let atributos: Set<SpeechTranscriber.ResultAttributeOption> = [.audioTimeRange, .transcriptionConfidence]
        let principal = SpeechTranscriber(locale: Locale(identifier: idioma), transcriptionOptions: [],
                                          reportingOptions: [.volatileResults, .fastResults], attributeOptions: atributos)
        let segundo = ingles
            ? SpeechTranscriber(locale: Locale(identifier: "en_US"), transcriptionOptions: [], reportingOptions: [],
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
                    for try await r in segundo.results where r.isFinal { palavrasIngles += Palavra.de(r) }
                } catch {
                    registro.error("leitura em inglês: \(error, privacy: .public)")
                }
            })
        }

        // ponytail: installTap foi deprecado no 27, mas a versão nova (com error:) ainda não tem refinamento em Swift
        let engine = AVAudioEngine()
        let mic = engine.inputNode
        mic.installTap(onBus: 0, bufferSize: 1024, format: mic.outputFormat(forBus: 0),
                       block: Self.tap(conversor: conversor, entrada: entrada) { n in Task { @MainActor in aoNivel(n) } })
        engine.prepare()
        try engine.start()
        self.engine = engine
        self.analyzer = analyzer
        self.entrada = entrada
    }

    /// Para o microfone, espera os modelos firmarem o fim da fala e devolve o que foi reconhecido.
    func parar() async throws -> Resultado {
        desligarMicrofone()
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch let erro as NSError where erro.domain == "SFSpeechErrorDomain" && erro.code == 1 {
            // "RecogRejected": com o detector de voz, um trecho já firmado na pausa seguido só de silêncio até o fim
            // faz o finalizar falhar (reproduzido com áudio sintetizado). O texto já firmado continua valendo.
            registro.notice("fim só com silêncio (RecogRejected); fica o que já firmou")
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

    /// Palavras em inglês já reconhecidas num intervalo do áudio (para fundir com um trecho em português).
    func ingles(de inicio: Double, ate fim: Double) -> [Palavra] {
        palavrasIngles.filter { $0.fim > inicio && $0.inicio < fim }
    }

    func cancelar() async {
        desligarMicrofone()
        leituras.forEach { $0.cancel() }
        leituras = []
        await analyzer?.cancelAndFinishNow()
        analyzer = nil
    }

    private func desligarMicrofone() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        entrada?.finish()
        entrada = nil
    }

    /// O bloco roda na thread de áudio. Fica `nonisolated` para o Swift 6 não herdar o MainActor
    /// (o que derruba o app com assert de isolamento na primeira chamada).
    nonisolated private static func tap(conversor: AnalyzerInputConverter,
                                        entrada: AsyncStream<AnalyzerInput>.Continuation,
                                        aoNivel: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        nonisolated(unsafe) let conversor = conversor  // usado só por esta thread de áudio
        return { buffer, _ in
            aoNivel(nivel(buffer))
            do {
                for pedaco in try conversor.convert(buffer, at: nil) { entrada.yield(pedaco) }
            } catch {
                registro.error("conversão de áudio falhou: \(error, privacy: .public)")
            }
        }
    }

    /// RMS em dB mapeado para 0…1 (−50 dB = silêncio, 0 dB = máximo).
    nonisolated private static func nivel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let amostras = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var rms: Float = 0
        vDSP_rmsqv(amostras, 1, &rms, vDSP_Length(buffer.frameLength))
        return min(1, max(0, (20 * log10(max(rms, 1e-6)) + 50) / 50))
    }
}
