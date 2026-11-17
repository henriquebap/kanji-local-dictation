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
    var vozes = Locutores(limiar: 0.6)
    let quem = [[1, 0, 0], [0.9, 0.1, 0], [0, 1, 0], [0.05, 1, 0], [1, 0.05, 0], [0, 0, 1]].map { vozes.identificar($0) }
    conferir("vozes viram locutores na ordem em que aparecem", "\(quem)", "[1, 1, 2, 2, 1, 3]")
    conferir("janela curta não abre locutor novo", "\(vozes.identificar([0.2, 0.4, -0.6], confiavel: false))", "2")
    conferir("janela curta entre duas iguais herda o vizinho",
             "\(Locutores.suavizar([1, 1, 2, 1, 2, 2], duracoes: [3, 3, 1, 3, 3, 3]))", "[1, 1, 1, 1, 2, 2]")
    conferir("janela longa não é ruído", "\(Locutores.suavizar([1, 2, 1], duracoes: [3, 3, 3]))", "[1, 2, 1]")
    let p = { (i: Double, f: Double) in Palavra(texto: " x", inicio: i, fim: f, confianca: 1) }
    // 0–1,6 s fecha na pausa de 0,4 s; 2,0–5,0 s passa de 3 s; a sobra de 0,5 s junta com a anterior.
    let palavras = [p(0, 0.4), p(0.5, 1.0), p(1.1, 1.6), p(2.0, 2.6), p(2.7, 3.5), p(3.6, 4.4), p(4.5, 5.0), p(5.1, 5.6)]
    conferir("janelas fecham na pausa e no máximo", "\(Locutores.janelas(palavras).map { [$0.lowerBound, $0.upperBound] })",
             "[[0, 3], [3, 8]]")
    conferir("pausa longa fecha a janela mesmo curta", "\(Locutores.janelas([p(0, 0.5), p(2.0, 3.0), p(3.1, 4.5)]).map { [$0.lowerBound, $0.upperBound] })",
             "[[0, 1], [1, 3]]")
    conferir("relógio de mais de uma hora", Transcricao.relogio(3725.4), "01:02:05")
    conferir("quem fala, na ordem", sessao.locutores.joined(separator: ", "), "Outros, Você, Locutor 2")
    conferir("duração vai até o fim do último trecho", "\(sessao.duracao)", "20.0")
    var renomeada = sessao
    conferir("renomear troca em todos os trechos", "\(renomeada.renomear("Outros", para: "  Lando\n"))", "true")
    conferir("nome novo nos turnos", renomeada.turnos().map(\.quem).joined(separator: ", "), "Lando, Você, Lando, Locutor 2")
    conferir("renomear o microfone", "\(renomeada.renomear("Você", para: "Henrique"))", "true")
    conferir("nome de outra voz é recusado", "\(renomeada.renomear("Henrique", para: "Lando"))", "false")
    var podcast = Transcricao(inicio: Date(timeIntervalSince1970: 0))
    podcast.adicionar(Trecho(inicio: 0, fim: 9, canal: .mac, texto: "What's been the best interaction that you've had with a fan, whether it's about F1 or sim racing?"))
    podcast.adicionar(Trecho(inicio: 10, fim: 14, canal: .mac, texto: "Honestly, just seeing the passion of people who love racing."))
    conferir("idioma principal de um podcast em inglês", podcast.idiomaPrincipal ?? "nil", "en")
    var reuniao = Transcricao(inicio: Date(timeIntervalSince1970: 0))
    reuniao.adicionar(Trecho(inicio: 0, fim: 9, canal: .mac, texto: "Hoje a gente faz o deploy da feature nova e abre o pull request antes do code review."))
    reuniao.adicionar(Trecho(inicio: 10, fim: 14, canal: .microfone, texto: "Beleza, eu cuido dos testes e do backend amanhã."))
    conferir("português com termos em inglês continua português", reuniao.idiomaPrincipal ?? "nil", "pt")
    conferir("voz do Mac não vira Você", "\(fala.renomear("Outros", para: "Você"))", "false")
    // Inglês que encosta no português: só entram as palavras onde o português não firmou nenhuma.
    let w = { (t: String, i: Double, f: Double) in Palavra(texto: t, inicio: i, fim: f, confianca: 0.9) }
    let fora = { (en: [Palavra], cobertos: [(inicio: Double, fim: Double)]) in
        Fusao.foraDoPortugues(en, cobertos: cobertos)
            .map { $0.map(\.texto).joined().trimmingCharacters(in: .whitespaces) }.joined(separator: " | ")
    }
    let colado = [w("You", 0.5, 1.0), w(" don't pretty", 1.0, 2.5), w(" Let's", 3.2, 3.6), w(" ship", 3.6, 4.0), w(" it.", 4.0, 4.5)]
    conferir("inglês logo depois do português entra", fora(colado, [(0.4, 1.1), (1.1, 2.4), (2.4, 3.0)]), "Let's ship it.")
    let entre = [w(" the", 2.5, 2.9), w(" We", 3.1, 3.5), w(" need", 3.5, 4.0), w(" more tests.", 4.0, 5.5), w(" German", 6.1, 6.5)]
    conferir("inglês entre dois trechos em português entra", fora(entre, [(2.4, 3.0), (6.0, 6.6)]), "We need more tests.")
    conferir("sobra de uma palavra na borda fica de fora", fora([w(" the", 3.05, 3.3)], [(2.4, 3.0)]), "")
    conferir("inglês sozinho entra inteiro", fora(colado, []), "You don't pretty Let's ship it.")
    let esticada = [w("Então", 0, 0.4), w(" entrega", 0.4, 1.0), w(" sip", 1.0, 3.2), w(" it on Friday", 3.2, 4.4)]
    conferir("palavra esticada sai e corta o trecho",
             Fusao.semEsticadas(esticada).map { $0.map(\.texto).joined() }.joined(separator: " |"), "Então entrega | it on Friday")
    conferir("nome vazio é recusado", "\(renomeada.renomear("Lando", para: "   "))", "false")
    conferir("renomeado sobrevive ao JSON", try! {
        let dados = try JSONEncoder().encode(renomeada)
        return try JSONDecoder().decode(Transcricao.self, from: dados).locutores.joined(separator: ", ")
    }(), "Lando, Henrique, Locutor 2")
    // Notas de carreira: o que entra no pacote do modo entrevista.
    conferir("nota da raiz e de pasta entram",
             "\(Notas.entra("apresentacao.md")) \(Notas.entra("experiencias/hob-tech.md"))", "true true")
    conferir("oculto, _, arquivo, agentes e não-.md ficam de fora",
             ["arquivo/context/CV.md", "_exports/skill/SKILL.md", ".obsidian/app.md", "CLAUDE.md", "Archive/x.md", "Untitled.canvas"]
                .map { "\(Notas.entra($0))" }.joined(separator: " "), "false false false false false false")
    conferir("nota obsoleta sai, rascunho e sem cabeçalho ficam",
             "\(Notas.obsoleta("---\nstatus: obsoleto\n---\n# X")) \(Notas.obsoleta("---\nstatus: rascunho\n---\nstatus: obsoleto")) \(Notas.obsoleta("# X"))",
             "true false false")
    conferir("pacote: raiz primeiro, em ordem, com o caminho",
             Notas.pacote([("projetos/b.md", "B"), ("z.md", " Z\n"), ("arquivo/a.md", "A"), ("a.md", "---\nstatus: obsoleto\n---")]),
             "<nota caminho=\"z.md\">\nZ\n</nota>\n\n<nota caminho=\"projetos/b.md\">\nB\n</nota>")
    // Modo entrevista: o turno do entrevistador pede resposta?
    let turnos = [
        "Tell me about yourself.", "so how did you measure that", "Legal, gostei. E como vocês mediram isso",
        "me conta um projeto que você liderou", "Qual a sua pretensão salarial", "Do you have any questions for us?",
        "Great, thanks.", "What we do here is mostly backend work.", "Como eu falei, o time é pequeno.",
        "O que a gente faz aqui é integração.", "Por isso a gente prefere remoto.", "Next step is a technical interview.",
    ]
    conferir("pede resposta: perguntas sim, afirmações e fechamento não",
             turnos.map { Pergunta.pedeResposta($0) ? "1" : "0" }.joined(), "111111000000")
    return falhas
}
