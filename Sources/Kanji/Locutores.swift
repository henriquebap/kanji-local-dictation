import Foundation

/// Quem é quem numa sessão, ao vivo: cada pedaço de fala vira um vetor da voz (ImpressaoDeVoz) e vai para o
/// locutor mais parecido, ou abre um novo. Os números saem na ordem em que cada voz aparece ("Locutor 1", "Locutor 2"…).
struct Locutores {
    /// Cosseno mínimo com a voz média de um locutor para ser ele. Medido em janelas de ~3 s tocadas pelo Mac e
    /// ouvidas pelo tap: a mesma voz deu 0,70–0,80 e vozes diferentes 0,01–0,20.
    let limiar: Float
    private(set) var centros: [[Float]] = []  // soma dos vetores normalizados de cada locutor

    init(limiar: Float) {
        self.limiar = limiar
    }

    /// Número do locutor (1, 2, …) para o vetor.
    /// - confiavel: false para uma janela curta (um "aham" de 0,3 s), cujo vetor sai abaixo do limiar até contra a
    ///   própria voz. Ela fica com o locutor mais parecido sem mexer na média dele e nunca abre um locutor novo.
    // ponytail: agrupamento guloso, sem rever decisões antigas; um locutor que nasce de um pedaço ruidoso fica.
    // Reagrupar tudo no fim da sessão (aglomerativo) se aparecerem locutores fantasmas.
    mutating func identificar(_ vetor: [Float], confiavel: Bool = true) -> Int {
        let v = Self.normalizado(vetor)
        let parecidos = centros.enumerated().map { ($0.offset, Self.cosseno($0.element, v)) }
        let melhor = parecidos.max(by: { $0.1 < $1.1 })
        if let melhor, !confiavel { return melhor.0 + 1 }
        if let melhor, melhor.1 >= limiar {
            centros[melhor.0] = zip(centros[melhor.0], v).map { $0 + $1 }
            return melhor.0 + 1
        }
        centros.append(v)
        return centros.count
    }

    /// Agrupa as palavras de um trecho em janelas de ~1,5 a 3 s para tirar a voz. Janela curta demais dá um vetor
    /// instável; longa demais junta duas pessoas. A janela fecha de preferência numa pausa, onde a troca acontece,
    /// e sempre numa pausa longa: sem isso uma janela atravessou a fala de outra pessoa que o reconhecedor não pegou.
    static func janelas(_ palavras: [Palavra], minimo: Double = 1.5, maximo: Double = 3) -> [Range<Int>] {
        var grupos: [Range<Int>] = []
        var inicio = 0
        for i in palavras.indices {
            let duracao = palavras[i].fim - palavras[inicio].inicio
            let pausa = i + 1 < palavras.count ? palavras[i + 1].inicio - palavras[i].fim : .infinity
            if duracao >= maximo || (duracao >= minimo && pausa >= 0.25) || pausa >= 1 || i == palavras.count - 1 {
                grupos.append(inicio..<(i + 1))
                inicio = i + 1
            }
        }
        // A sobra do fim, curta demais, fica com a janela anterior.
        if grupos.count > 1, let ultima = grupos.last,
           palavras[ultima.upperBound - 1].fim - palavras[ultima.lowerBound].inicio < minimo,
           palavras[ultima.lowerBound].inicio - palavras[ultima.lowerBound - 1].fim < 1 {
            grupos.removeLast()
            grupos[grupos.count - 1] = grupos[grupos.count - 1].lowerBound..<ultima.upperBound
        }
        return grupos
    }

    /// Uma janela curta entre duas do mesmo locutor é quase sempre ruído (risada, "é", sobreposição): fica com ele.
    static func suavizar(_ rotulos: [Int], duracoes: [Double], curta: Double = 2.5) -> [Int] {
        guard rotulos.count >= 3 else { return rotulos }
        var saida = rotulos
        for i in 1..<(rotulos.count - 1)
        where saida[i - 1] == rotulos[i + 1] && rotulos[i] != saida[i - 1] && duracoes[i] < curta {
            saida[i] = saida[i - 1]
        }
        return saida
    }

    static func cosseno(_ a: [Float], _ b: [Float]) -> Float {
        let produto = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        let normas = (a.reduce(0) { $0 + $1 * $1 } * b.reduce(0) { $0 + $1 * $1 }).squareRoot()
        return normas > 0 ? produto / normas : 0
    }

    private static func normalizado(_ v: [Float]) -> [Float] {
        let norma = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return norma > 0 ? v.map { $0 / norma } : v
    }
}
