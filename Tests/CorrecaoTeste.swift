import Foundation
import os
// Casos reais de ditados: a trava de fidelidade precisa aceitar correções boas e descartar traduções e cortes.
let registro = Logger(subsystem: "teste", category: "teste")
@MainActor func testar() -> Int {
    let casos: [(String, String, String, Bool)] = [
        ("traduziu o inglês", "Machine learning engineering. McDonald's o API Claude API inteligência artificial artificial inteligence My name Henrique My car is Jeddah. I am 20 years 23 years old",
         "Machine learning engineering. McDonald's, API, Claude, API, inteligência artificial, inteligência artificial. Meu nome é Henrique, meu carro é Jeddah. Tenho 20 anos, 23 anos.", false),
        ("correção boa", "Eu acho que ainda tá meio burrado essa parte de inglês. mas a parte de português aparentemente tá boa tem colocado um ponto final ali onde não deveria",
         "Eu acho que ainda tá meio burrado essa parte de inglês. Mas a parte de português aparentemente tá boa, tem colocado um ponto final ali onde não deveria.", true),
        ("glossário", "Isso vou fazer um deploy no bees base e abrir um pull request no Cloud para revisar.",
         "Isso vou fazer um deploy no Supabase e abrir um pull request no Cloud para revisar.", true),
        ("traduziu frase curta", "My name is Henrique and I'm 23 years old", "Meu nome é Henrique e tenho 23 anos", false),
        ("inventou palavra", "Eu acho que ainda tá meio.", "Eu acho que ainda tá meio bugado.", false),
        ("traduziu termo", "Vou fazer o deploy usando database do Stabase.", "Vou fazer o deploy usando o banco de dados do Supabase.", false),
        ("trocou termo", "Vou fazer o deploy usando database do Stabase.", "Vou fazer o deploy usando database do Supabase.", true),
        ("lista sem a frase", "Quero adicionar 5 coisas na minha sacola de mercado. Primeiro banana. Dois creme de leite. Três arroz. Quatro. Feijão e cinco café",
         "1. Banana\n2. Creme de leite\n3. Arroz\n4. Feijão\n5. Café", false),
        ("lista completa", "Quero adicionar 5 coisas na minha sacola de mercado. Primeiro banana. Dois creme de leite. Três arroz. Quatro. Feijão e cinco café",
         "Quero adicionar 5 coisas na minha sacola de mercado:\n1. Banana\n2. Creme de leite\n3. Arroz\n4. Feijão\n5. Café", true),
    ]
    var falhas = 0
    for (nome, bruto, saida, esperado) in casos {
        let aceitou = Correcao.fiel(saida, a: bruto, glossario: ["Claude", "Supabase", "deploy", "pull request", "bugado"])
        print(aceitou == esperado ? "ok   " : "FALHA", aceitou ? "aceita  " : "descarta", "←", nome)
        if aceitou != esperado { falhas += 1 }
    }
    return falhas
}
@main struct T {
    static func main() async {
        let falhas = await testar() + testarRevisao()
        if falhas > 0 { exit(1) }
    }
}
