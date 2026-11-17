import Foundation

/// Modo entrevista: se o turno do entrevistador pede uma resposta do candidato. Só isso decide se o painel abre;
/// qual história contar fica com a nuvem, que lê a pergunta inteira junto com as notas.
/// O reconhecimento de fala pontua mal (pergunta sem "?", ponto no lugar), então a regra olha as palavras.
// ponytail: regra de pistas em PT e EN. Se a precisão ou o recall ficarem baixos em entrevistas reais
// (Tests/perguntas-entrevista.tsv), passar os casos duvidosos ao modelo do Mac.
enum Pergunta {
    static func pedeResposta(_ turno: String) -> Bool {
        guard let ultima = frases(turno).last else { return false }
        if ultima.hasSuffix("?") { return true }
        let frase = normalizar(ultima)
        // "…e você liderava né", "…you owned the rollout too right": a tag no fim pede confirmação.
        if tags.contains(where: { frase.hasSuffix(" " + $0) }) { return true }
        // Com algo depois da pista: "era isso que eu queria saber" fecha o assunto, não pergunta.
        if pistasEmQualquerLugar.contains(where: { pista in
            frase.range(of: pista).map { !frase[$0.upperBound...].trimmingCharacters(in: .whitespaces).isEmpty } ?? false
        }) { return true }
        return oracoes(frase).contains { interrogativa(semMuleta($0)) }
    }

    /// A frase inteira e o que vem depois de cada "e", "and", "então", "so": sem pontuação, a pergunta chega colada
    /// num comentário ("legal gostei e como vocês mediram isso").
    private static func oracoes(_ frase: String) -> [String] {
        let palavras = frase.split(separator: " ").map(String.init)
        return [frase] + palavras.indices.dropLast().filter { conectivos.contains(palavras[$0]) && $0 > 0 }
            .map { palavras[($0 + 1)...].joined(separator: " ") }
    }

    /// Frases do turno, com a pontuação final. Uma última frase que é só agradecimento ou "ok" não pede nada, mesmo
    /// depois de uma pergunta: a pergunta já foi respondida e o entrevistador está fechando.
    static func frases(_ turno: String) -> [String] {
        var frases: [String] = []
        var atual = ""
        for c in turno {
            atual.append(c)
            if ".?!".contains(c) {
                frases.append(atual.trimmingCharacters(in: .whitespaces))
                atual = ""
            }
        }
        frases.append(atual.trimmingCharacters(in: .whitespaces))
        return frases.filter { $0.contains(where: \.isLetter) }
    }

    private static func normalizar(_ frase: String) -> String {
        frase.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet.alphanumerics.union(["'", " "]).inverted).joined(separator: " ")
            .split(separator: " ").joined(separator: " ")
    }

    /// Tira do começo as palavras de apoio ("então", "so", "legal", "hum"), que escondem a pergunta que vem depois.
    private static func semMuleta(_ frase: String) -> String {
        var palavras = frase.split(separator: " ").map(String.init)
        while let primeira = palavras.first, muletas.contains(primeira), palavras.count > 1 { palavras.removeFirst() }
        return palavras.joined(separator: " ")
    }

    private static func interrogativa(_ frase: String) -> Bool {
        let palavras = frase.split(separator: " ").map(String.init)
        guard let primeira = palavras.first else { return false }
        let segunda = palavras.dropFirst().first ?? ""
        // "o que", "por que", "em que", "de qual" são uma palavra de pergunta só; "por isso…" não é.
        let composta = primeira == "o" && segunda == "que"
            || ["por", "em", "de", "com", "pra", "para", "a"].contains(primeira) && ["que", "quê", "qual", "quais", "quanto", "quantos"].contains(segunda)
        let tamanho = composta ? 2 : interrogativos.contains(primeira) ? 1 : 0
        if tamanho > 0 {
            // "what we do here is…", "o que a gente faz aqui é…", "como eu falei…": a palavra de pergunta abre uma
            // afirmação. Em inglês a pergunta inverte ("what do you"); em português, quem pergunta fala de "você".
            let resto = palavras.dropFirst(tamanho)
            let sujeito = resto.first ?? ""
            return !(afirmacao.contains(sujeito) || sujeito == "a" && resto.dropFirst().first == "gente")
        }
        return comecos.contains { frase == $0 || frase.hasPrefix($0 + " ") }
    }

    private static let muletas: Set<String> = [
        "so", "and", "ok", "okay", "alright", "well", "great", "cool", "nice", "perfect", "right", "now", "then", "uh", "um",
        "hmm", "então", "e", "tá", "ta", "beleza", "legal", "bom", "perfeito", "show", "ótimo", "agora", "hum", "tipo", "enfim",
        "certo", "entendi", "bacana", "massa", "olha",
    ]
    private static let interrogativos: Set<String> = [
        "what", "what's", "whats", "why", "how", "when", "where", "which", "who", "whose",
        "como", "quando", "onde", "qual", "quais", "quem", "quanto", "quantos", "quantas",
    ]
    /// Sujeito logo depois da palavra de pergunta = afirmação, não pergunta.
    private static let afirmacao: Set<String> = ["i", "we", "they", "he", "she", "our", "eu", "nós", "nos", "ele", "ela", "eles"]
    private static let comecos = [
        "can you", "could you", "would you", "will you", "do you", "did you", "have you", "are you", "were you", "is there",
        "was there", "is that", "tell me", "walk me", "talk me", "describe", "explain", "give me", "share", "any questions",
        "anything else", "você pode", "você poderia", "você já", "você tem", "você teve", "você usa", "você usou",
        "você conhece", "você sabe", "você acha", "você prefere", "você consegue", "você gosta", "pode me", "poderia",
        "me conta", "me conte", "me fala", "me fale", "me explica", "me explique", "conta", "conte", "descreve", "descreva",
        "explica", "explique", "dá um exemplo", "tem alguma", "alguma pergunta", "alguma dúvida",
    ]
    private static let conectivos: Set<String> = ["e", "and", "então", "so", "mas", "but"]
    private static let tags = ["né", "right", "certo", "correct", "não é", "isn't it", "is that right", "é isso", "confere"]
    private static let pistasEmQualquerLugar = [
        "me dá um exemplo", "me dê um exemplo", "adoraria ouvir", "adoraria saber", "adoraria entender", "want to understand",
        "want to hear", "would love to", "gostaria que você", "tell me", "walk me through", "love to hear", "like to hear", "i'm curious", "curious to", "can you", "could you",
        "me conta", "me conte", "me fala", "me fale", "queria entender", "queria saber", "gostaria de saber",
        "gostaria de entender", "gostaria de ouvir", "quero entender", "quero saber", "fala um pouco", "conta um pouco",
        "você pode", "você poderia", "questions for us", "pergunta pra gente", "pergunta para a gente", "alguma dúvida",
    ]
}
