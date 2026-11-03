import Foundation

/// Revisão em tempo real: cada trecho que o reconhecedor firma (a cada pausa) é revisado e anexado.
/// Testado com o modelo de 3B: ele corrige bem palavras dentro do trecho, mas erra ao decidir listas e se o
/// trecho continua a frase anterior. Por isso listas e junções são regras aqui, e o modelo só corrige o trecho.
@MainActor
final class RevisaoAoVivo {
    private(set) var trechos: [String] = []
    private var itemAtual = 0  // número do último item de lista; 0 = fora de lista
    private var itemPendente = false  // o trecho acabou em "terceiro lugar": o item vem no próximo
    private let revisar: (String, String) async -> String  // (trecho, texto anterior) → trecho revisado
    private let glossario: [String]
    private let comecaComNome: (String) -> Bool

    init(glossario: [String], comecaComNome: @escaping (String) -> Bool = { _ in false },
         revisar: @escaping (String, String) async -> String) {
        self.revisar = revisar
        self.glossario = glossario
        self.comecaComNome = comecaComNome
    }

    var texto: String { Escrita.juntar(trechos) }

    /// - pausa: silêncio, em segundos, entre o fim do trecho anterior e o começo deste (nil se desconhecido).
    func processar(_ bruto: String, pausa: Double? = nil) async {
        let entrada = itemPendente ? "\(Escrita.ordinal(itemAtual + 1)) \(bruto)" : bruto
        let (dito, itens, pendente) = Escrita.dividirLista(entrada, proximo: itemAtual + 1)
        itemPendente = pendente
        // "café e | quarto…": o "e" que sobrou entre dois itens não encerra a lista.
        let antes = itemAtual > 0 && !itens.isEmpty && Escrita.soLigacao(dito) ? "" : dito
        if !antes.isEmpty {
            let saindoDeLista = itemAtual > 0
            itemAtual = 0
            let revisado = await revisar(antes, String(texto.suffix(300)))
            anexar(revisado, depoisDeLista: saindoDeLista, pausa: pausa)
        }
        for item in itens {
            itemAtual += 1
            if itemAtual == 1, let ultimo = trechos.last { trechos[trechos.count - 1] = Escrita.abrirLista(ultimo) }
            trechos.append("\n\(itemAtual). \(Escrita.maiuscula(item))")
        }
    }

    private func anexar(_ trecho: String, depoisDeLista: Bool, pausa: Double?) {
        guard !depoisDeLista else { return trechos.append("\n" + trecho) }  // texto depois da lista: linha nova
        guard let ultimo = trechos.last, Escrita.continua(ultimo, trecho, pausa: pausa) else { return trechos.append(trecho) }
        if ultimo.hasSuffix(".") { trechos[trechos.count - 1] = String(ultimo.dropLast()) }  // o ponto era só a pausa
        trechos.append(Escrita.minuscula(trecho, glossario: glossario, comecaComNome: comecaComNome))
    }
}

/// Regras de texto puras (sem modelo), testadas em Tests/RevisaoTeste.swift.
enum Escrita {
    /// Palavras com que uma frase não costuma terminar: se o trecho anterior acabou numa delas, a pausa cortou a frase.
    static let naoFecham: Set<String> = [
        "o", "a", "os", "as", "um", "uma", "de", "do", "da", "dos", "das", "no", "na", "nos", "nas", "em", "com", "para",
        "pra", "por", "pelo", "pela", "que", "e", "mas", "ou", "se", "meio", "tipo", "muito", "mais", "é", "tá", "vai",
        "the", "of", "to", "and", "with", "in", "for", "on",
    ]
    /// Palavras que, no começo do trecho, indicam que ele continua a frase anterior.
    static let conectivos: Set<String> = ["e", "mas", "que", "porque", "pra", "para", "de", "do", "da", "com", "ou", "quando", "pois"]

    /// Pausa abaixo disso entre dois trechos é respiração no meio da frase, não fim de frase.
    static let pausaDeFrase = 0.7

    static func continua(_ anterior: String, _ novo: String, pausa: Double? = nil) -> Bool {
        guard let ultima = palavras(anterior).last, let primeira = palavras(novo).first, let fim = anterior.last else { return false }
        // Sem ponto, o reconhecedor não fechou a frase: o trecho novo continua ("não foi | Mas aparentemente").
        guard ".!?:".contains(fim) else { return true }
        guard fim == "." else { return false }
        // Com a pausa medida, ela decide; só uma frase que acabou em "de", "que"… continua mesmo após pausa longa.
        if let pausa { return pausa < pausaDeFrase || naoFecham.contains(ultima) }
        return naoFecham.contains(ultima) || conectivos.contains(primeira)
    }

    static func juntar(_ trechos: [String]) -> String {
        trechos.reduce("") { texto, trecho in
            texto.isEmpty || trecho.hasPrefix("\n") ? texto + trecho : texto + " " + trecho
        }
    }

    // MARK: Listas

    private static let ordinais: [String: Int] = [
        "primeiro": 1, "primeira": 1, "segundo": 2, "segunda": 2, "terceiro": 3, "terceira": 3, "quarto": 4, "quarta": 4,
        "quinto": 5, "quinta": 5, "sexto": 6, "sexta": 6, "sétimo": 7, "sétima": 7, "oitavo": 8, "oitava": 8,
        "nono": 9, "nona": 9, "décimo": 10, "décima": 10,
    ]
    private static let cardinais: [String: Int] = [
        "dois": 2, "duas": 2, "três": 3, "quatro": 4, "cinco": 5, "seis": 6, "sete": 7, "oito": 8, "nove": 9, "dez": 10,
    ]

    static func ordinal(_ n: Int) -> String {
        ordinais.first { $0.value == n && $0.key.hasSuffix("o") }?.key ?? "item"
    }

    /// Separa o que vem antes da lista e os itens ditados ("primeiro banana, dois café").
    /// Um número só abre item se for o próximo esperado: "dois" no meio de uma frase comum não vira item.
    /// `pendente`: o trecho acabou num marcador sem conteúdo ("terceiro lugar"), então o item vem no próximo.
    static func dividirLista(_ trecho: String, proximo: Int) -> (antes: String, itens: [String], pendente: Bool) {
        var antes: [Substring] = []
        var itens: [[Substring]] = []
        var esperado = proximo
        for palavra in trecho.split(separator: " ") {
            let chave = palavra.lowercased().trimmingCharacters(in: .punctuationCharacters)
            let numero = ordinais[chave] ?? (esperado > 1 ? cardinais[chave] : nil)
            if numero == esperado {
                itens.append([])
                esperado += 1
            } else if itens.isEmpty {
                antes.append(palavra)
            } else {
                itens[itens.count - 1].append(palavra)
            }
        }
        let limpar = { (s: String) in s.trimmingCharacters(in: CharacterSet(charactersIn: " ,:;.")) }
        guard !itens.isEmpty else { return (trecho, [], false) }
        let textos = distribuir(itens.map { limpar(semEnchimento($0).joined(separator: " ")) })
        let abertura = antes.last.map { ["em", "no", "na"].contains($0.lowercased()) } == true ? antes.dropLast() : antes[...]
        return (limpar(abertura.joined(separator: " ")), textos.filter { !$0.isEmpty }, textos.last?.isEmpty == true)
    }

    /// "quarto e quinto lugar vai ser Ferrari e McLaren": marcadores seguidos e itens ditos juntos no fim.
    /// Se o último tem exatamente uma parte por marcador, cada parte vai para o seu número.
    private static func distribuir(_ textos: [String]) -> [String] {
        var saida: [String] = []
        var vazios = 0
        for texto in textos {
            guard !texto.isEmpty else { vazios += 1; continue }
            let partes = texto.replacingOccurrences(of: ", ", with: " e ").components(separatedBy: " e ")
            saida += vazios > 0 && partes.count == vazios + 1 ? partes : Array(repeating: "", count: vazios) + [texto]
            vazios = 0
        }
        return saida + Array(repeating: "", count: vazios)
    }

    /// Trecho que é só "e", "e o", "agora": ligação entre itens, não texto.
    static func soLigacao(_ trecho: String) -> Bool {
        palavras(trecho).allSatisfy { conectivos.contains($0) || naoFecham.contains($0) || $0 == "agora" }
    }

    /// "primeiro lugar vai ser banana e" → "banana": tira o que é só jeito de falar em volta do item.
    private static func semEnchimento(_ palavras: [Substring]) -> [Substring] {
        let antes: Set<String> = ["lugar", "item", "é", "vai", "ser", "seria", "a", "o"]
        let depois: Set<String> = ["e", "é", "a", "o"]
        var resto = palavras[...]
        while let p = resto.first, antes.contains(p.lowercased().trimmingCharacters(in: .punctuationCharacters)) { resto = resto.dropFirst() }
        while let p = resto.last, depois.contains(p.lowercased().trimmingCharacters(in: .punctuationCharacters)) { resto = resto.dropLast() }
        return Array(resto)
    }

    /// "Quero comprar três coisas." → "Quero comprar três coisas:" quando o próximo trecho abre a lista.
    static func abrirLista(_ frase: String) -> String {
        frase.trimmingCharacters(in: CharacterSet(charactersIn: " .,")) + ":"
    }

    static func maiuscula(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    /// Minúscula no começo do trecho que continua a frase, sem estragar sigla ou nome ("API", "Claude", "Ferrari").
    /// Termo do glossário fica com a grafia do glossário ("Bugado" → "bugado", "claude" → "Claude").
    static func minuscula(_ s: String, glossario: [String] = [], comecaComNome: (String) -> Bool = { _ in false }) -> String {
        guard let primeira = s.split(separator: " ").first else { return s }
        let limpa = primeira.trimmingCharacters(in: .punctuationCharacters)
        if let termo = glossario.first(where: { $0.caseInsensitiveCompare(limpa) == .orderedSame }) {
            return termo + s.dropFirst(limpa.count)
        }
        guard !comecaComNome(s), primeira.dropFirst().allSatisfy({ $0.isLowercase || !$0.isLetter }) else { return s }
        return s.prefix(1).lowercased() + s.dropFirst()
    }

    private static func palavras(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter }.map(String.init)
    }
}
