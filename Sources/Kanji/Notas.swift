import Foundation

/// As notas de carreira da pessoa (uma pasta do Obsidian, por exemplo), lidas na hora de perguntar. O Kanji nunca
/// guarda cópia: o que muda na pasta vale na próxima pergunta.
enum Notas {
    // ponytail: o pacote vai inteiro no prompt (com cache). ~300 mil caracteres são ~80 mil tokens; acima disso,
    // buscar só as notas que tocam a pergunta (NLEmbedding).
    static let limite = 300_000

    /// Fica de fora, pelo caminho relativo à pasta: o que é oculto ou começa com "_" (configuração e exportações do
    /// Obsidian), o material antigo ("arquivo", "archive") e as instruções para agentes (CLAUDE.md, AGENTS.md).
    static func entra(_ caminho: String) -> Bool {
        let partes = caminho.split(separator: "/")
        guard caminho.hasSuffix(".md"), let nome = partes.last, !["CLAUDE.md", "AGENTS.md"].contains(nome) else { return false }
        return !partes.contains { $0.hasPrefix(".") || $0.hasPrefix("_") || ["arquivo", "archive"].contains($0.lowercased()) }
    }

    /// `status: obsoleto` (ou `obsolete`) no cabeçalho YAML: a nota foi superada e só confundiria a resposta.
    static func obsoleta(_ texto: String) -> Bool {
        guard texto.hasPrefix("---") else { return false }
        let cabecalho = texto.dropFirst(3).components(separatedBy: "\n---").first ?? ""
        return cabecalho.split(separator: "\n").contains {
            let linha = $0.lowercased().replacingOccurrences(of: " ", with: "")
            return linha == "status:obsoleto" || linha == "status:obsolete"
        }
    }

    /// As notas que entram, cada uma marcada com o caminho para a resposta citar de onde veio. As da raiz primeiro
    /// (perfil, regras, apresentação), depois as pastas, em ordem alfabética: a mesma ordem a cada pergunta deixa o
    /// começo do prompt igual, e o cache do provedor aproveita.
    static func pacote(_ notas: [(caminho: String, texto: String)]) -> String {
        notas.filter { entra($0.caminho) && !obsoleta($0.texto) }
            .sorted { ($0.caminho.contains("/") ? 1 : 0, $0.caminho) < ($1.caminho.contains("/") ? 1 : 0, $1.caminho) }
            .map { "<nota caminho=\"\($0.caminho)\">\n\($0.texto.trimmingCharacters(in: .whitespacesAndNewlines))\n</nota>" }
            .joined(separator: "\n\n")
    }

    /// Lê os `.md` da pasta e monta o pacote. `quantas` é o número de notas que entraram.
    /// Um arquivo do iCloud que saiu do disco falha na leitura ("Resource deadlock"): o erro sobe com o nome dele.
    static func ler(_ pasta: URL) throws -> (pacote: String, quantas: Int) {
        let base = pasta.standardizedFileURL.path(percentEncoded: false)
        guard let itens = FileManager.default.enumerator(at: pasta, includingPropertiesForKeys: nil) else { return ("", 0) }
        var notas: [(caminho: String, texto: String)] = []
        for case let url as URL in itens {
            let caminho = String(url.standardizedFileURL.path(percentEncoded: false).dropFirst(base.count)).trimmingCharacters(in: ["/"])
            guard entra(caminho) else { continue }
            notas.append((caminho, try String(contentsOf: url, encoding: .utf8)))
        }
        let pacote = pacote(notas)
        return (pacote, pacote.components(separatedBy: "<nota caminho=").count - 1)
    }
}
