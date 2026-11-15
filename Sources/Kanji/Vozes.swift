import CoreML
import CryptoKit
import Foundation
import Observation
import os

/// Impressão digital da voz: WeSpeaker ResNet34 do pyannote community-1, convertido para CoreML pela Fluid Inference
/// (CC-BY-4.0, créditos no NOTICE). Dois modelos: `FBank` transforma 10 s de áudio a 16 kHz em 80×998 coeficientes;
/// `Embedding` recebe esses coeficientes e uma máscara de 589 quadros e devolve um vetor de 256 números da voz que
/// fala nos quadros marcados. A máscara deixa tirar a voz de qualquer pedaço dos 10 s sem recortar o áudio.
/// Não é código de terceiros: os pesos são dados opcionais, baixados quando a pessoa liga a separação de locutores.
final class ImpressaoDeVoz: @unchecked Sendable {  // MLModel é seguro para previsões concorrentes
    static let taxa = 16_000.0
    static let amostras = 160_000  // 10 s
    static let quadros = 589
    static let lote = 32  // maior lote que os dois modelos aceitam

    private let fbank: MLModel
    private let embedding: MLModel

    /// - pasta: onde estão `FBank.mlmodelc` e `Embedding.mlmodelc`.
    init(pasta: URL) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        fbank = try MLModel(contentsOf: pasta.appending(path: "FBank.mlmodelc"), configuration: config)
        embedding = try MLModel(contentsOf: pasta.appending(path: "Embedding.mlmodelc"), configuration: config)
    }

    /// Um vetor por intervalo, em segundos dentro do pedaço de áudio (até 10 s a 16 kHz; o que faltar vira silêncio).
    func vetores(audio: ArraySlice<Float>, intervalos: [(Double, Double)]) throws -> [[Float]] {
        guard !intervalos.isEmpty else { return [] }
        let entrada = try MLMultiArray(shape: [1, 1, NSNumber(value: Self.amostras)], dataType: .float32)
        entrada.withUnsafeMutableBufferPointer(ofType: Float.self) { destino, _ in
            destino.initialize(repeating: 0)
            for (i, amostra) in audio.prefix(Self.amostras).enumerated() { destino[i] = amostra }
        }
        let saida = try fbank.prediction(from: MLDictionaryFeatureProvider(dictionary: ["audio": entrada]))
        guard let coeficientes = saida.featureValue(for: "fbank_features")?.multiArrayValue else { throw Falha.saida }
        let porLote = stride(from: 0, to: intervalos.count, by: Self.lote).map { Array(intervalos[$0..<min($0 + Self.lote, intervalos.count)]) }
        return try porLote.flatMap { try vetoresDoLote(coeficientes, $0) }
    }

    private func vetoresDoLote(_ coeficientes: MLMultiArray, _ intervalos: [(Double, Double)]) throws -> [[Float]] {
        let n = intervalos.count
        let (bandas, colunas) = (80, 998)
        let repetidos = try MLMultiArray(shape: [NSNumber(value: n), 1, NSNumber(value: bandas), NSNumber(value: colunas)],
                                         dataType: .float32)
        let mascaras = try MLMultiArray(shape: [NSNumber(value: n), NSNumber(value: Self.quadros)], dataType: .float32)
        // A saída do FBank vem com cada linha alinhada em 1008 posições (strides [80640, 80640, 1008, 1]), não 998:
        // copiar o buffer de uma vez embaralhava os coeficientes e todas as vozes ficavam parecidas.
        let linha = coeficientes.strides[2].intValue
        coeficientes.withUnsafeBufferPointer(ofType: Float.self) { origem in
            repetidos.withUnsafeMutableBufferPointer(ofType: Float.self) { destino, _ in
                for i in 0..<n {
                    for b in 0..<bandas {
                        for c in 0..<colunas { destino[(i * bandas + b) * colunas + c] = origem[b * linha + c] }
                    }
                }
            }
        }
        let porQuadro = Double(Self.amostras) / Self.taxa / Double(Self.quadros)
        mascaras.withUnsafeMutableBufferPointer(ofType: Float.self) { destino, _ in
            for (i, (inicio, fim)) in intervalos.enumerated() {
                for q in 0..<Self.quadros {
                    let centro = (Double(q) + 0.5) * porQuadro
                    destino[i * Self.quadros + q] = centro >= inicio && centro < fim ? 1 : 0
                }
            }
        }
        let saida = try embedding.prediction(from: MLDictionaryFeatureProvider(
            dictionary: ["fbank_features": repetidos, "weights": mascaras]))
        guard let vetores = saida.featureValue(for: "embedding")?.multiArrayValue else { throw Falha.saida }
        let dimensao = vetores.count / n
        return vetores.withUnsafeBufferPointer(ofType: Float.self) { origem in
            (0..<n).map { i in Array(origem[(i * dimensao)..<((i + 1) * dimensao)]) }
        }
    }

    enum Falha: Error { case saida }
}

/// Os últimos minutos do áudio da sessão a 16 kHz mono, para tirar a voz de cada trecho depois que ele firma
/// (sem forçar o fim do trecho, o reconhecedor firma de 30 s a 1 min depois da fala). 3 min ≈ 11 MB.
final class MemoriaDeAudio: Sendable {
    static let segundos = 180.0
    private let estado = OSAllocatedUnfairLock(initialState: (amostras: [Float](), descartadas: 0))

    init() {
        // Tudo reservado de uma vez: crescer por dobra copiaria até 11 MB sob a trava, na fila do áudio.
        estado.withLockUnchecked { $0.amostras.reserveCapacity(Int((Self.segundos + 11) * ImpressaoDeVoz.taxa)) }
    }

    /// Chamado na thread de áudio. O tempo de cada amostra é a posição dela desde o começo, igual ao do reconhecedor.
    // ponytail: descarta o começo em blocos de 10 s com um memmove sob trava na thread de áudio; uma fila circular
    // se aparecer estalo ou atraso na captura.
    func anexar(_ novas: UnsafeBufferPointer<Float>) {
        estado.withLockUnchecked { e in  // o ponteiro só vive nesta chamada, na mesma thread
            e.amostras.append(contentsOf: novas)
            let excesso = e.amostras.count - Int(Self.segundos * ImpressaoDeVoz.taxa)
            if excesso > Int(10 * ImpressaoDeVoz.taxa) {
                e.amostras.removeFirst(excesso)
                e.descartadas += excesso
            }
        }
    }

    /// Até onde já há áudio, em segundos desde o começo da sessão.
    var duracao: Double {
        estado.withLock { Double($0.descartadas + $0.amostras.count) / ImpressaoDeVoz.taxa }
    }

    /// O áudio entre dois instantes da sessão, ou nil se já saiu da memória.
    func audio(de inicio: Double, ate fim: Double) -> [Float]? {
        estado.withLock { e in
            let a = Int(inicio * ImpressaoDeVoz.taxa) - e.descartadas
            let b = min(Int(fim * ImpressaoDeVoz.taxa) - e.descartadas, e.amostras.count)
            return a >= 0 && b > a ? Array(e.amostras[a..<b]) : nil
        }
    }
}

/// Os pesos da separação de locutores: opcionais, baixados do Hugging Face numa revisão fixa e conferidos pelo
/// SHA-256 de cada arquivo. Arquivo diferente do esperado não é carregado.
@MainActor @Observable
final class ModeloDeVozes {
    enum Estado: Equatable { case ausente, baixando(Double), pronto, erro(String) }

    static let shared = ModeloDeVozes()
    nonisolated static let revisao = "7eab74f3463c736418d0eb10296261ae581146c9"
    nonisolated static let origem = "https://huggingface.co/FluidInference/speaker-diarization-coreml/resolve/\(revisao)/"
    nonisolated static let pasta = URL.applicationSupportDirectory.appending(path: "Kanji/Modelos/locutores-\(revisao.prefix(7))")
    nonisolated private static let conferido = pasta.appending(path: ".conferido")
    nonisolated static let arquivos = [
        ("Embedding.mlmodelc/analytics/coremldata.bin", "8d6706436639b53830b4dbe8aaf9c9a843f7f582d63e16f3cb8bb7c6ccd58682"),
        ("Embedding.mlmodelc/coremldata.bin", "4a705bac27d151d9642f37609296042a15602a42253039e0921dc9e75da7e004"),
        ("Embedding.mlmodelc/metadata.json", "1854371eb6b438fb8aeac96afb45c999af7902581c06afdfcd7ff3cb1ce66be5"),
        ("Embedding.mlmodelc/model.mil", "22fa958aef72a561c21f874a07cbdcd30fdf40ee961c0bc2fb67c119273b46d3"),
        ("Embedding.mlmodelc/weights/weight.bin", "99356b2985b8d43880a657024d941d450b38820451ccff903f76ed4e52d1868b"),
        ("FBank.mlmodelc/analytics/coremldata.bin", "0e8bd3a8b82ac123580989f490e4d9245127c535857630b543311268accc3f0a"),
        ("FBank.mlmodelc/coremldata.bin", "57ac436bb0671cbb5527a339134d695f752eb77f7a18966b93c6835335595759"),
        ("FBank.mlmodelc/metadata.json", "2623785f5d186893b82d01e84aa33a7704ef763c3309e02055f22dc9d871ce9a"),
        ("FBank.mlmodelc/model.mil", "27aaeb21569e81bdbe2eef87789f50a37cfea800039bd134448a9417de2f30ed"),
        ("FBank.mlmodelc/weights/weight.bin", "9e83fdd3ea78064b078069e4d9141603c61c47a27fd19e7e3142ff7476f8db36"),
    ]

    private(set) var estado: Estado = FileManager.default.fileExists(atPath: conferido.path) ? .pronto : .ausente

    /// Confere de novo os 10 arquivos (~15 MB, dezenas de ms) antes de carregar: a pasta fica em Application Support,
    /// onde qualquer processo da pessoa pode trocar um arquivo depois do download.
    nonisolated static func conferir() throws {
        for (caminho, esperado) in arquivos {
            let dados = try Data(contentsOf: pasta.appending(path: caminho))
            guard hash(dados) == esperado else { throw Falha.hashDiferente(caminho) }
        }
    }

    /// Apaga o modelo que não passou na conferência; a pessoa baixa de novo pelos Ajustes.
    func descartar() {
        try? FileManager.default.removeItem(at: Self.pasta)
        estado = .ausente
    }

    nonisolated private static func hash(_ dados: Data) -> String {
        SHA256.hash(data: dados).map { String(format: "%02x", $0) }.joined()
    }

    func baixar() {
        if case .baixando = estado { return }
        guard estado != .pronto else { return }
        estado = .baixando(0)
        Task {
            let temporaria = FileManager.default.temporaryDirectory.appending(path: "kanji-locutores-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: temporaria) }
            do {
                for (i, (caminho, esperado)) in Self.arquivos.enumerated() {
                    guard let url = URL(string: Self.origem + caminho) else { throw URLError(.badURL) }
                    let (baixado, resposta) = try await URLSession.shared.download(from: url)
                    guard (resposta as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    let dados = try Data(contentsOf: baixado)
                    guard Self.hash(dados) == esperado else { throw Falha.hashDiferente(caminho) }
                    let destino = temporaria.appending(path: caminho)
                    try FileManager.default.createDirectory(at: destino.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try dados.write(to: destino)
                    estado = .baixando(Double(i + 1) / Double(Self.arquivos.count))
                }
                try? FileManager.default.removeItem(at: Self.pasta)
                try FileManager.default.createDirectory(at: Self.pasta.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: temporaria, to: Self.pasta)
                try Data().write(to: Self.conferido)
                estado = .pronto
                registro.notice("modelo de locutores baixado e conferido")
            } catch {
                registro.error("download do modelo de locutores: \(error.localizedDescription, privacy: .public)")
                estado = .erro(String(localized: "Não consegui baixar o modelo de locutores: \(error.localizedDescription)"))
            }
        }
    }

    enum Falha: LocalizedError {
        case hashDiferente(String)
        var errorDescription: String? {
            switch self {
            case .hashDiferente(let arquivo): String(localized: "o arquivo \(arquivo) veio diferente do esperado")
            }
        }
    }
}
