import Foundation
import NaturalLanguage

/// Um trecho firmado de uma sessão longa, com o tempo em segundos desde o começo da sessão.
struct Trecho: Codable, Equatable, Sendable {
    enum Canal: String, Codable, Sendable { case mac, microfone }

    let inicio: Double
    let fim: Double
    let canal: Canal
    /// "Locutor 1", "Locutor 2"… com a separação de vozes ligada, ou o nome que a pessoa deu ao renomear.
    var locutor: String?
    let texto: String

    /// Quem fala no arquivo. Fica em português: é conteúdo salvo, não interface.
    var quem: String { locutor ?? (canal == .microfone ? "Você" : "Outros") }
}

/// Uma sessão de transcrição do áudio do Mac. O JSON é a fonte; o Markdown sai dele para ler e levar
/// para outro lugar (Obsidian, um e-mail).
struct Transcricao: Codable, Identifiable, Sendable {
    var id = UUID()
    let inicio: Date
    var fim: Date?
    private(set) var trechos: [Trecho] = []

    init(inicio: Date) {
        self.inicio = inicio
    }

    /// Microfone e áudio do Mac firmam cada um no seu ritmo: o trecho entra na posição do seu início.
    mutating func adicionar(_ trecho: Trecho) {
        let posicao = trechos.lastIndex { $0.inicio <= trecho.inicio }.map { $0 + 1 } ?? 0
        trechos.insert(trecho, at: posicao)
    }

    struct Turno: Equatable {
        let inicio: Double
        let quem: String
        var texto: String
    }

    /// Um parágrafo por turno: trechos seguidos do mesmo turno viram um parágrafo só, com a hora do primeiro.
    func turnos() -> [Turno] {
        var turnos: [Turno] = []
        var anterior: Trecho?
        for trecho in trechos {
            if let anterior, let turno = turnos.last, Self.mesmoTurno(anterior, trecho, desde: turno.inicio) {
                turnos[turnos.count - 1].texto += " " + trecho.texto
            } else {
                turnos.append(Turno(inicio: trecho.inicio, quem: trecho.quem, texto: trecho.texto))
            }
            anterior = trecho
        }
        return turnos
    }

    func markdown() -> String {
        let corpo = turnos().map { "**[\(Self.relogio($0.inicio))] \($0.quem):** \($0.texto)" }
        return ([titulo] + corpo).joined(separator: "\n\n") + "\n"
    }

    var titulo: String { "# Transcrição — \(data)" }

    /// "16/11/2026 16:36", para títulos.
    var data: String { Self.titulo.string(from: inicio) }

    /// Quem fala, na ordem em que aparece.
    var locutores: [String] {
        trechos.reduce(into: []) { lista, trecho in if !lista.contains(trecho.quem) { lista.append(trecho.quem) } }
    }

    /// Idioma em que a maior parte foi falada ("pt", "en"…): o que for gerado a partir dela sai nesse idioma, sem
    /// traduzir. Pelo texto dos trechos, sem os rótulos de quem fala, que são do Kanji e sempre em português.
    var idiomaPrincipal: String? {
        let reconhecedor = NLLanguageRecognizer()
        reconhecedor.processString(trechos.map(\.texto).joined(separator: " "))
        return reconhecedor.dominantLanguage?.rawValue
    }

    /// Segundos de áudio até o último trecho.
    var duracao: Double { trechos.map(\.fim).max() ?? 0 }

    /// Troca o nome de quem fala em todos os trechos. Devolve false para um nome vazio ou que já é de outra pessoa,
    /// para duas vozes não virarem uma sem querer.
    mutating func renomear(_ antigo: String, para novo: String) -> Bool {
        let nome = String(novo.filter { !$0.isNewline }.trimmingCharacters(in: .whitespaces).prefix(40))
        // "Você" é quem gravou (o resumo trata assim): uma voz do Mac não vira "Você".
        guard !nome.isEmpty, nome == antigo || !locutores.contains(nome), nome != "Você" || antigo == "Você" else { return false }
        for i in trechos.indices where trechos[i].quem == antigo { trechos[i].locutor = nome }
        return true
    }

    // MARK: - Arquivos

    /// JSON (a fonte) e Markdown, reescritos inteiros e de forma atômica.
    /// - base: o caminho sem extensão. Para um arquivo que já existe, o de onde ele foi lido: a pessoa pode ter
    ///   renomeado no Finder, e gravar pelo nome da data criaria uma segunda cópia ao lado.
    // ponytail: reescreve tudo a cada trecho; numa sessão de horas são poucos MB. JSON Lines se aparecer no perfil.
    func gravar(base: URL) throws {
        try FileManager.default.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
        let codificador = JSONEncoder()
        codificador.dateEncodingStrategy = .iso8601
        codificador.outputFormatting = [.prettyPrinted, .sortedKeys]
        try codificador.encode(self).write(to: base.appendingPathExtension("json"), options: .atomic)
        try Data(markdown().utf8).write(to: base.appendingPathExtension("md"), options: .atomic)
    }

    static func ler(_ url: URL) throws -> Transcricao {
        let decodificador = JSONDecoder()
        decodificador.dateDecodingStrategy = .iso8601
        return try decodificador.decode(Transcricao.self, from: Data(contentsOf: url))
    }

    /// O resumo e o feedback ficam ao lado, com o mesmo nome: no Finder os arquivos aparecem juntos.
    static func resumo(de base: URL, _ analise: Analise = .resumo) -> URL {
        base.deletingLastPathComponent().appending(path: "\(base.lastPathComponent) \(analise.rawValue).md")
    }

    /// Se `atual` continua a fala de quem disse `anterior` ou começa um parágrafo novo no arquivo.
    /// - desde: início do parágrafo em andamento, para um monólogo não virar um bloco de minutos.
    /// Medido com `say`: dentro de uma fala os trechos ficam a ~0,8 s um do outro; entre falas, a 4 s.
    // ponytail: limiares fixos; sem separar vozes, duas pessoas que se emendam em menos de 2 s ficam juntas.
    static func mesmoTurno(_ anterior: Trecho, _ atual: Trecho, desde inicio: Double) -> Bool {
        anterior.quem == atual.quem && atual.inicio - anterior.fim < 2 && atual.fim - inicio < 60
    }

    /// 3725,4 s → "01:02:05".
    static func relogio(_ segundos: Double) -> String {
        let s = max(0, Int(segundos))
        return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }

    /// Nome dos arquivos: ordena por data no Finder e não usa ":", que o Finder troca por "/".
    var nomeDoArquivo: String { Self.arquivo.string(from: inicio) }

    private static let titulo = formato("dd/MM/yyyy HH:mm")
    private static let arquivo = formato("yyyy-MM-dd HH-mm-ss")

    private static func formato(_ padrao: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = padrao
        return f
    }
}

/// O que a nuvem gera de uma transcrição. O valor bruto é o fim do nome do arquivo: não traduzir.
enum Analise: String, CaseIterable, Sendable {
    case resumo
    case entrevista  // feedback para quem gravou (o "Você"): pontos fortes e o que melhorar
}
