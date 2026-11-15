import Foundation

// Regras de lista e junção da revisão ao vivo, com trechos como o reconhecedor entrega (um por pausa).
@MainActor func testarRevisao() async -> Int {
    var falhas = 0
    func conferir(_ nome: String, _ obtido: String, _ esperado: String) {
        let ok = obtido == esperado
        print(ok ? "ok   " : "FALHA", nome, ok ? "" : "\n  obtido:   \(obtido.debugDescription)\n  esperado: \(esperado.debugDescription)")
        if !ok { falhas += 1 }
    }
    func rodar(_ trechos: [String], pausas: [Double?] = []) async -> String {
        let r = RevisaoAoVivo(glossario: ["Claude", "Supabase", "bugado"], comecaComNome: Fusao.comecaComNome) { trecho, _ in trecho }  // sem modelo: só as regras
        for (i, t) in trechos.enumerated() { await r.processar(t, pausa: i < pausas.count ? pausas[i] : nil) }
        return r.texto
    }
    conferir("lista em trechos", await rodar(["Quero comprar três coisas no mercado.", "Primeiro banana.", "Dois café.", "Três creme de leite."]),
             "Quero comprar três coisas no mercado:\n1. Banana\n2. Café\n3. Creme de leite")
    conferir("lista num trecho só", await rodar(["Quero comprar primeiro banana segundo café terceiro arroz."]),
             "Quero comprar:\n1. Banana\n2. Café\n3. Arroz")
    conferir("texto depois da lista", await rodar(["Lista.", "Primeiro banana.", "Segundo café.", "Depois eu passo no banco."]),
             "Lista:\n1. Banana\n2. Café\nDepois eu passo no banco.")
    conferir("parágrafo depois da lista", await rodar(["Lista.", "Primeiro banana.", "Depois eu passo no banco.", "Amanhã eu volto.", "E pago a conta."]),
             "Lista:\n1. Banana\nDepois eu passo no banco. Amanhã eu volto e pago a conta.")
    conferir("lista com 'lugar' e conectivos", await rodar(["Vou fazer uma lista agora em primeiro lugar banana segundo lugar creme de leite terceiro lugar café e quarta e quinto lugar vai ser Ferrari e McLaren."]),
             "Vou fazer uma lista agora:\n1. Banana\n2. Creme de leite\n3. Café\n4. Ferrari\n5. McLaren")
    let g = ["Claude", "Claude Code", "Supabase", "API", "deploy"]
    conferir("glossário em pares", Fusao.aplicarGlossario("vou fazer um deploy no Cloud code utilizando a PI deles.", g),
             "vou fazer um deploy no Claude Code utilizando API deles.")
    conferir("glossário em palavra solta", Fusao.aplicarGlossario("o database é do Stabase,", g), "o database é do Supabase,")
    conferir("par legítimo intocado", Fusao.aplicarGlossario("comi a pizza e subi a base", g), "comi a pizza e subi a base")
    conferir("pausa curta é a mesma frase", await rodar(["Tenho.", "Dois anos de experiência."], pausas: [nil, 0.4]),
             "Tenho dois anos de experiência.")
    conferir("pausa longa é frase nova", await rodar(["Já vi que não foi.", "Mas ficou mais rápido."], pausas: [nil, 1.2]),
             "Já vi que não foi. Mas ficou mais rápido.")
    conferir("nome próprio mantém maiúscula", await rodar(["O quinto vai ser.", "Ferrari e McLaren."], pausas: [nil, 0.4]),
             "O quinto vai ser Ferrari e McLaren.")
    conferir("item cortado entre trechos", await rodar(["Lista em primeiro lugar banana segundo lugar creme de leite terceiro lugar", "Café e quarto e quinto lugar vai ser Ferrari e McLaren."]),
             "Lista:\n1. Banana\n2. Creme de leite\n3. Café\n4. Ferrari\n5. McLaren")
    conferir("'e' solto não fecha a lista", await rodar(["Lista em primeiro lugar banana segundo lugar café terceiro lugar arroz e", "E quarto e quinto lugar vai ser Ferrari e McLaren."]),
             "Lista:\n1. Banana\n2. Café\n3. Arroz\n4. Ferrari\n5. McLaren")
    conferir("sem ponto continua a frase", await rodar(["Já vi que não foi", "Mas aparentemente ficou mais rápido."], pausas: [nil, 1.2]),
             "Já vi que não foi mas aparentemente ficou mais rápido.")
    conferir("maiúscula no meio da frase", Fusao.semMaiusculaNoMeio("Depois de Tudo que eu falei Ele pode rolar. Mas o Henrique usa Supabase no GitHub.", glossario: ["Supabase"]),
             "Depois de tudo que eu falei ele pode rolar. Mas o Henrique usa Supabase no GitHub.")
    let pt = [Palavra(texto: "Ferrari", inicio: 0, fim: 0.5, confianca: 0.9), Palavra(texto: " e", inicio: 0.5, fim: 0.6, confianca: 0.9),
              Palavra(texto: " McLaren.", inicio: 0.6, fim: 1.1, confianca: 0.5)]
    let en = [Palavra(texto: "Ferrari", inicio: 0, fim: 0.5, confianca: 0.6), Palavra(texto: " to", inicio: 0.6, fim: 1.1, confianca: 0.5)]
    conferir("fusão não troca nome por palavra que não soa igual", Fusao.fundir(pt: pt, en: en, glossario: []), "Ferrari e McLaren.")
    conferir("número comum não vira item", await rodar(["Eu comprei dois cafés hoje."]), "Eu comprei dois cafés hoje.")
    conferir("pausa no meio da frase", await rodar(["Eu acho que ainda tá meio.", "Bugado essa parte."]),
             "Eu acho que ainda tá meio bugado essa parte.")
    conferir("conectivo continua", await rodar(["Vou fazer o deploy no Supabase.", "E abrir um pull request."]),
             "Vou fazer o deploy no Supabase e abrir um pull request.")
    conferir("frase nova", await rodar(["Vou fazer o deploy.", "Amanhã eu reviso."]), "Vou fazer o deploy. Amanhã eu reviso.")
    conferir("nome protegido", await rodar(["Vou pedir para o.", "Claude revisar."]), "Vou pedir para o Claude revisar.")
    conferir("chave de API não entra no histórico", "\(Historico.pareceSegredo("chave-ficticia-AbCdEf0123456789xyzXYZ0123456789"))", "true")
    conferir("texto comum entra no histórico", "\(Historico.pareceSegredo("Minha expectativa é de R$ 100/h no modelo PJ"))", "false")
    conferir("aprende nome trocado pela nuvem", "\(Aprendizado.trocas(bruto: "Vou pedir pro Cláudio revisar o jogo do Baloobírus.", final: "Vou pedir pro Claude revisar o jogo do Buffalo Bills."))",
             "[\"Claude\", \"Buffalo Bills\"]")
    conferir("ortografia e maiúscula não viram termo", "\(Aprendizado.trocas(bruto: "Eu selicionei aqui. Tá bom o gil vai vir", final: "Eu selecionei aqui. Tá bom, o Gil vai vir."))", "[]")
    conferir("variável de ambiente não entra", "\(Historico.pareceSegredo("export OPENAI_KEY=chave-ficticia-AbCdEf0123456789xyzXYZ0123456789"))", "true")
    conferir("URL com senha não entra", "\(Historico.pareceSegredo("postgres://admin:senha@db.exemplo.com/app"))", "true")
    conferir("link entra no histórico", "\(Historico.pareceSegredo("https://github.com/henriquebap/kanji-local-dictation/pull/12345678901234"))", "false")
    var sessao = Transcricao(inicio: Date(timeIntervalSince1970: 0))
    sessao.adicionar(Trecho(inicio: 4, fim: 9, canal: .mac, texto: "Bem-vindos ao episódio."))
    sessao.adicionar(Trecho(inicio: 15, fim: 17, canal: .mac, texto: "Hoje é deploy."))
    sessao.adicionar(Trecho(inicio: 11, fim: 14, canal: .microfone, texto: "Oi, pessoal."))  // firmou depois, falou antes
    sessao.adicionar(Trecho(inicio: 18, fim: 20, canal: .mac, locutor: "Locutor 2", texto: "Obrigado."))
    let md = sessao.markdown().split(separator: "\n", omittingEmptySubsequences: true).dropFirst().joined(separator: "\n")
    conferir("transcrição em turnos, na ordem da fala", md, """
        **[00:00:04] Outros:** Bem-vindos ao episódio.
        **[00:00:11] Você:** Oi, pessoal.
        **[00:00:15] Outros:** Hoje é deploy.
        **[00:00:18] Locutor 2:** Obrigado.
        """)
    var fala = Transcricao(inicio: Date(timeIntervalSince1970: 0))
    for (inicio, fim, texto) in [(0.0, 3.0, "Um."), (3.8, 6.0, "Dois."), (10.0, 12.0, "Três."),
                                 (12.5, 40.0, "Quatro."), (40.5, 70.0, "Cinco.")] {
        fala.adicionar(Trecho(inicio: inicio, fim: fim, canal: .mac, texto: texto))
    }
    let paragrafos = fala.markdown().split(separator: "\n", omittingEmptySubsequences: true).dropFirst().joined(separator: "\n")
    conferir("turno quebra na pausa e no monólogo longo", paragrafos, """
        **[00:00:00] Outros:** Um. Dois.
        **[00:00:10] Outros:** Três. Quatro.
        **[00:00:40] Outros:** Cinco.
        """)
    conferir("relógio de mais de uma hora", Transcricao.relogio(3725.4), "01:02:05")
    return falhas
}
