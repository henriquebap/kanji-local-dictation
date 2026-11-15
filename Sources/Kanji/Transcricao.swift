import Foundation

/// Um trecho firmado de uma sessão longa, com o tempo em segundos desde o começo da sessão.
struct Trecho: Codable, Equatable, Sendable {
    enum Canal: String, Codable, Sendable { case mac, microfone }

    let inicio: Double
    let fim: Double
    let canal: Canal
    var locutor: String?  // "Locutor 1", "Locutor 2"… quando a separação de vozes estiver ligada
    let texto: String

    /// Quem fala no arquivo. Fica em português: é conteúdo salvo, não interface.
    var quem: String { canal == .microfone ? "Você" : locutor ?? "Outros" }
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

    /// Um parágrafo por turno: trechos seguidos do mesmo turno viram um parágrafo só, com a hora do primeiro.
    func markdown() -> String {
        var turnos: [(primeiro: Trecho, texto: String)] = []
        var anterior: Trecho?
        for trecho in trechos {
            if let anterior, let turno = turnos.last, Self.mesmoTurno(anterior, trecho, desde: turno.primeiro.inicio) {
                turnos[turnos.count - 1].texto += " " + trecho.texto
            } else {
                turnos.append((trecho, trecho.texto))
            }
            anterior = trecho
        }
        let corpo = turnos.map { "**[\(Self.relogio($0.0.inicio))] \($0.0.quem):** \($0.1)" }
        return (["# Transcrição — \(Self.titulo.string(from: inicio))"] + corpo).joined(separator: "\n\n") + "\n"
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
