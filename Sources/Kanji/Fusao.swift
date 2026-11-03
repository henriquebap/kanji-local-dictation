import AppKit
import NaturalLanguage
import Speech

/// Uma palavra reconhecida, com o trecho do áudio e a confiança do modelo.
struct Palavra: Sendable {
    let texto: String  // inclui o espaço e a pontuação que o modelo devolveu (" deploy,")
    let inicio: Double
    let fim: Double
    let confianca: Double

    static func de(_ resultado: SpeechTranscriber.Result) -> [Palavra] {
        resultado.text.runs.compactMap { run in
            guard let tempo = run.audioTimeRange else { return nil }
            return Palavra(texto: String(resultado.text[run.range].characters), inicio: tempo.start.seconds,
                           fim: tempo.end.seconds, confianca: run.transcriptionConfidence ?? 0)
        }
    }

    var limpo: String { texto.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) }
}

/// Junta duas transcrições do mesmo áudio (português + inglês) palavra por palavra.
/// O reconhecedor de português erra termos em inglês ("Dloy", "seuase"); o de inglês, no mesmo
/// trecho de tempo, costuma acertar ("deploy", "superbase"). Testado: o modelo local de 3B não
/// consegue fazer essa fusão sozinho, por isso ela é determinística.
@MainActor
enum Fusao {
    static func fundir(pt: [Palavra], en: [Palavra], glossario: [String]) -> String {
        guard !pt.isEmpty else { return en.map(\.texto).joined().trimmingCharacters(in: .whitespaces) }
        guard !en.isEmpty else { return pt.map(\.texto).joined().trimmingCharacters(in: .whitespaces) }
        // Fala toda em inglês: o reconhecedor de inglês fica bem mais confiante na média.
        if media(en) > media(pt) + 0.1 { return en.map(\.texto).joined().trimmingCharacters(in: .whitespaces) }

        var usados = Set<Int>()
        var saida = ""
        for p in pt {
            let trecho = sobrepostas(p, en).filter { !usados.contains($0) }
            if let troca = troca(p, en: trecho.map { en[$0] }, glossario: glossario) {
                usados.formUnion(trecho)
                let pontuacao = p.texto.last.map { ",.!?".contains($0) ? String($0) : "" } ?? ""
                saida += " " + troca + pontuacao
            } else {
                saida += p.texto
            }
        }
        return saida.trimmingCharacters(in: .whitespaces)
    }

    /// Palavra que não existe nem em português nem em inglês e é parecida com um termo do glossário vira o termo
    /// ("Stabase" → "Supabase"). Roda em todo trecho, com ou sem o reconhecedor de inglês.
    static func aplicarGlossario(_ texto: String, _ glossario: [String]) -> String {
        let simples = glossario.filter { !$0.contains(" ") }
        guard !glossario.isEmpty else { return texto }
        return emPares(texto, glossario).split(separator: " ", omittingEmptySubsequences: false).map { pedaco in
            let token = String(pedaco)
            let palavra = token.trimmingCharacters(in: .punctuationCharacters)
            guard palavra.count >= 4,
                  !simples.contains(where: { $0.caseInsensitiveCompare(palavra) == .orderedSame }),
                  !existe(palavra, "pt_BR"), !existe(palavra, "en"),
                  let termo = doGlossario(palavra, simples)
            else { return token }
            return token.replacingOccurrences(of: palavra, with: termo)
        }.joined(separator: " ")
    }

    /// Duas palavras seguidas que juntas lembram um termo: "Cloud code" → "Claude Code", "a PI" → "API".
    /// Só troca quando o termo tem espaço ou quando uma das duas não é palavra de verdade (ou é uma letra só),
    /// para não mexer em pares legítimos.
    private static func emPares(_ texto: String, _ glossario: [String]) -> String {
        var tokens = texto.split(separator: " ").map(String.init)
        var i = 0
        while i + 1 < tokens.count {
            let a = tokens[i].trimmingCharacters(in: .punctuationCharacters)
            let b = tokens[i + 1].trimmingCharacters(in: .punctuationCharacters)
            let suspeita = { (p: String) in p.count <= 2 || (!existe(p, "pt_BR") && !existe(p, "en")) }
            let jaETermo = { (p: String) in glossario.contains { $0.caseInsensitiveCompare(p) == .orderedSame } }
            if !a.isEmpty, !b.isEmpty, !jaETermo(a), !jaETermo(b), let termo = doGlossario(a + b, glossario),
               "\(a) \(b)".caseInsensitiveCompare(termo) != .orderedSame,
               termo.contains(" ") || suspeita(a) || suspeita(b) {
                let pontuacao = String(tokens[i + 1].reversed().prefix { $0.isPunctuation }.reversed())
                tokens.replaceSubrange(i...(i + 1), with: [termo + pontuacao])
            }
            i += 1
        }
        return tokens.joined(separator: " ")
    }

    private static func troca(_ p: Palavra, en: [Palavra], glossario: [String]) -> String? {
        guard !en.isEmpty else { return nil }
        let candidato = en.map(\.limpo).joined(separator: " ")
        // 1. Termo do glossário, comparado de forma aproximada ("superbase" ≈ "Supabase").
        if p.confianca < 0.9, let termo = doGlossario(candidato, glossario) ?? doGlossario(p.limpo, glossario) {
            return termo
        }
        // 2. A palavra não existe em português e a do inglês existe (ou quase: "deploi" → "deploy").
        // Tem de soar parecido: nome próprio também não existe em português, e "McLaren" virava "to".
        guard p.confianca < 0.85, !existe(p.limpo, "pt_BR"),
              distancia(p.limpo, candidato) * 2 <= max(p.limpo.count, candidato.count) else { return nil }
        return emIngles(candidato)
    }

    /// Palavras em inglês que ocupam boa parte do mesmo trecho de áudio.
    private static func sobrepostas(_ p: Palavra, _ en: [Palavra]) -> [Int] {
        en.indices.filter { i in
            let comum = min(p.fim, en[i].fim) - max(p.inicio, en[i].inicio)
            return comum / max(p.fim - p.inicio, 0.01) >= 0.4 || comum / max(en[i].fim - en[i].inicio, 0.01) >= 0.6
        }
    }

    private static func doGlossario(_ s: String, _ glossario: [String]) -> String? {
        let alvo = s.replacingOccurrences(of: " ", with: "")
        guard alvo.count >= 2 else { return nil }
        return glossario.first { termo in
            let t = termo.replacingOccurrences(of: " ", with: "")
            return distancia(alvo, t) * 3 <= t.count  // até 1/3 das letras diferente
        }
    }

    private static func emIngles(_ s: String) -> String? {
        if s.split(separator: " ").allSatisfy({ existe(String($0), "en") }) { return s }
        guard !s.contains(" "),
              let palpite = NSSpellChecker.shared.guesses(forWordRange: NSRange(location: 0, length: s.utf16.count), in: s,
                                                          language: "en", inSpellDocumentWithTag: 0)?.first,
              !palpite.contains(" "), distancia(s, palpite) <= 2
        else { return nil }
        return palpite
    }

    /// O reconhecedor abre com maiúscula cada pedaço que ele mesmo fecha, mesmo no meio da frase
    /// ("já vi que não foi Mas aparentemente", "Depois de Tudo"). Palavra comum fora do começo de frase
    /// volta para minúscula; nome, sigla e termo do glossário ficam como estão.
    static func semMaiusculaNoMeio(_ texto: String, glossario: [String]) -> String {
        var nomes = Set<String>()
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = texto
        tagger.setLanguage(.portuguese, range: texto.startIndex..<texto.endIndex)
        tagger.enumerateTags(in: texto.startIndex..<texto.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tipo, faixa in
            if tipo == .personalName || tipo == .placeName || tipo == .organizationName {
                texto[faixa].split(separator: " ").forEach { nomes.insert(String($0)) }
            }
            return true
        }
        var abreFrase = true
        return texto.split(separator: " ", omittingEmptySubsequences: false).map { pedaco in
            let token = String(pedaco)
            defer { abreFrase = token.last.map { ".!?:\n".contains($0) } ?? abreFrase }
            let palavra = token.trimmingCharacters(in: .punctuationCharacters)
            guard !abreFrase, let primeira = palavra.first, primeira.isUppercase,
                  palavra.dropFirst().allSatisfy(\.isLowercase), !nomes.contains(palavra),
                  !glossario.contains(where: { $0.caseInsensitiveCompare(palavra) == .orderedSame }),
                  existe(palavra.lowercased(), "pt_BR")
            else { return token }
            return token.replacingOccurrences(of: palavra, with: palavra.lowercased())
        }.joined(separator: " ")
    }

    /// O trecho começa com nome de pessoa, lugar ou empresa ("Ferrari e McLaren", "Henrique vai…")?
    /// O corretor ortográfico erra isso nos dois sentidos (aceita "ferrari", recusa "bugado"); o NLTagger acerta.
    static func comecaComNome(_ trecho: String) -> Bool {
        guard let primeira = trecho.firstIndex(where: \.isLetter) else { return false }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = trecho
        tagger.setLanguage(.portuguese, range: trecho.startIndex..<trecho.endIndex)
        let (tipo, _) = tagger.tag(at: primeira, unit: .word, scheme: .nameType)
        return tipo == .personalName || tipo == .placeName || tipo == .organizationName
    }

    static func existe(_ palavra: String, _ idioma: String) -> Bool {
        guard !palavra.isEmpty else { return true }
        let erro = NSSpellChecker.shared.checkSpelling(of: palavra, startingAt: 0, language: idioma, wrap: false,
                                                       inSpellDocumentWithTag: 0, wordCount: nil)
        return erro.location == NSNotFound
    }

    private static func media(_ ps: [Palavra]) -> Double {
        ps.map(\.confianca).reduce(0, +) / Double(max(ps.count, 1))
    }

    /// Distância de Levenshtein, sem diferenciar maiúsculas.
    static func distancia(_ a: String, _ b: String) -> Int {
        let x = Array(a.lowercased()), y = Array(b.lowercased())
        guard !x.isEmpty else { return y.count }
        guard !y.isEmpty else { return x.count }
        var linha = Array(0...y.count)
        for i in 1...x.count {
            var diagonal = linha[0]
            linha[0] = i
            for j in 1...y.count {
                let acima = linha[j]
                linha[j] = min(linha[j] + 1, linha[j - 1] + 1, diagonal + (x[i - 1] == y[j - 1] ? 0 : 1))
                diagonal = acima
            }
        }
        return linha[y.count]
    }
}
