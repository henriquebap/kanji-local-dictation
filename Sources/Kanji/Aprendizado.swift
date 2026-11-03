import Foundation

/// Glossário que aprende com a revisão da nuvem. Cada troca que o modelo grande faz ("Cláudio" → Claude,
/// "Baloobírus" → Buffalo Bills) é contada; da segunda vez em diante o termo entra no glossário e passa a valer
/// também no modelo do Mac e nas regras locais, sem internet.
@MainActor
enum Aprendizado {
    static let chave = "aprendido"  // [termo: vezes que a revisão trocou algo por ele]
    static let vezesParaAprender = 2

    static var contagem: [String: Int] {
        UserDefaults.standard.dictionary(forKey: chave) as? [String: Int] ?? [:]
    }

    static var termos: [String] {
        contagem.filter { $0.value >= vezesParaAprender }.keys.sorted()
    }

    static func registrar(bruto: String, final: String) {
        var nova = contagem
        for termo in Set(trocas(bruto: bruto, final: final)) { nova[termo, default: 0] += 1 }  // conta uma vez por ditado
        UserDefaults.standard.set(nova, forKey: chave)
    }

    static func esquecer(_ termo: String) {
        var nova = contagem
        nova[termo] = nil
        UserDefaults.standard.set(nova, forKey: chave)
    }

    /// Trechos curtos que o revisor trocou por um termo de fora do português (jargão em inglês, marca) ou por um nome
    /// (maiúscula no meio da frase: o corretor do macOS aceita "Claude" como palavra do português).
    /// Acento, maiúscula e pontuação não contam ("selicionei" → "selecionei" é só ortografia); reescrita longa também não.
    static func trocas(bruto: String, final: String) -> [String] {
        let antes = tokens(bruto).map(\.texto)
        let marcados = tokens(final)
        let depois = marcados.map(\.texto)
        var saiu = Set<Int>()
        var entrou = Set<Int>()
        for mudanca in depois.map(normal).difference(from: antes.map(normal)) {
            switch mudanca {
            case .remove(let i, _, _): saiu.insert(i)
            case .insert(let j, _, _): entrou.insert(j)
            }
        }
        // As palavras que não mudaram aparecem na mesma ordem dos dois lados: entre duas delas, o que saiu
        // de um lado foi trocado pelo que entrou do outro.
        var (i, j, achados) = (0, 0, [String]())
        while i < antes.count || j < depois.count {
            var de: [String] = []
            var para: [String] = []
            var nome = false
            while i < antes.count, saiu.contains(i) { de.append(antes[i]); i += 1 }
            while j < depois.count, entrou.contains(j) {
                para.append(depois[j])
                nome = nome || (depois[j].first?.isUppercase == true && !marcados[j].abreFrase)
                j += 1
            }
            guard !de.isEmpty || !para.isEmpty else { i += 1; j += 1; continue }
            let termo = para.joined(separator: " ")
            if (1...4).contains(de.count), (1...3).contains(para.count),
               normal(de.joined(separator: " ")) != normal(termo),
               nome || para.contains(where: { !Fusao.existe($0.lowercased(), "pt_BR") }) {
                achados.append(termo)
            }
        }
        return achados
    }

    /// Palavras sem pontuação; `abreFrase`: vem no começo do texto ou depois de ponto, onde maiúscula não indica nome.
    private static func tokens(_ s: String) -> [(texto: String, abreFrase: Bool)] {
        var saida: [(texto: String, abreFrase: Bool)] = []
        var abre = true
        for cru in s.split(whereSeparator: \.isWhitespace) {
            let texto = cru.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
            if !texto.isEmpty { saida.append((texto, abre)) }
            abre = cru.last.map { ".!?:".contains($0) } ?? abre
        }
        return saida
    }

    private static func normal(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
