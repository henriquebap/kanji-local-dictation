import Foundation

/// Precisão e recall do detector de perguntas em dois conjuntos rotulados escritos por outro autor, sem ver o código
/// (rótulo, idioma e o turno do entrevistador). A regra foi ajustada olhando os erros de `perguntas-entrevista.tsv`
/// (desenvolvimento): a meta vale só para `perguntas-entrevista-teste.tsv`. Devolve as falhas.
/// `--modelo` mede também o modelo do Mac sozinho e o caminho híbrido (precisa de Apple Intelligence; leva minutos).
func avaliarPerguntas() async -> Int {
    var classificadores: [(String, (String) async -> Bool)] = [("regra", { Pergunta.pedeResposta($0) })]
    if CommandLine.arguments.contains("--modelo") {
        classificadores += [("modelo", { await PerguntaNoModelo.pede($0) ?? false }),
                            ("híbrido", { await Pergunta.pedeRespostaComModelo($0) })]
    }
    var falhas = 0
    for (nome, classificar) in classificadores {
        _ = await medirPerguntas("Tests/perguntas-entrevista.tsv", conjunto: "desenvolvimento", nome: nome, classificar)
        // A meta é do caminho que o app usa, o híbrido (medido em 17/11/2026: 0,90 e 0,90 no teste). Sem o modelo,
        // a regra sozinha tem um piso contra regressão (estava em 0,90 e 0,75).
        let (precisao, recall) = nome == "híbrido" ? (0.85, 0.90) : (0.85, 0.70)
        let ok = await medirPerguntas("Tests/perguntas-entrevista-teste.tsv", conjunto: "teste", nome: nome,
                                      precisao: precisao, recall: recall, classificar)
        if nome == classificadores.last?.0 {
            print(ok ? "ok   " : "FALHA", String(format: "detector de perguntas (%@) no teste: precisão ≥ %.2f, recall ≥ %.2f",
                                                 nome, precisao, recall))
            falhas += ok ? 0 : 1
        }
    }
    return falhas
}

private func medirPerguntas(_ arquivo: String, conjunto: String, nome: String, precisao minimaP: Double = 0,
                            recall minimoR: Double = 0, _ classificar: (String) async -> Bool) async -> Bool {
    guard let tsv = try? String(contentsOfFile: arquivo, encoding: .utf8) else {
        print("FALHA perguntas: \(arquivo) não encontrado")
        return false
    }
    var placar: [String: (vp: Int, fp: Int, fn: Int, vn: Int)] = [:]
    var erros: [String] = []
    let comeco = Date.now
    var total = 0
    for linha in tsv.split(separator: "\n") {
        let campos = linha.split(separator: "\t", maxSplits: 2).map(String.init)
        guard campos.count == 3 else { continue }
        let (esperado, idioma, turno) = (campos[0] == "1", campos[1], campos[2])
        let obtido = await classificar(turno)
        total += 1
        for chave in [idioma, "total"] {
            var p = placar[chave] ?? (0, 0, 0, 0)
            switch (esperado, obtido) {
            case (true, true): p.vp += 1
            case (false, true): p.fp += 1
            case (true, false): p.fn += 1
            case (false, false): p.vn += 1
            }
            placar[chave] = p
        }
        if esperado != obtido { erros.append("  \(nome) \(conjunto) \(esperado ? "perdeu" : "falso  ") [\(idioma)] \(turno)") }
    }
    let media = Date.now.timeIntervalSince(comeco) / Double(max(1, total)) * 1000
    for chave in ["pt", "en", "total"] {
        guard let p = placar[chave] else { continue }
        let precisao = Double(p.vp) / Double(max(1, p.vp + p.fp)), recall = Double(p.vp) / Double(max(1, p.vp + p.fn))
        print(String(format: "      perguntas, %@, %@, %@: precisão %.2f, recall %.2f (vp %d, fp %d, fn %d, vn %d)%@",
                     nome, conjunto, chave, precisao, recall, p.vp, p.fp, p.fn, p.vn,
                     chave == "total" ? String(format: ", %.0f ms por turno", media) : ""))
    }
    if CommandLine.arguments.contains("--erros") { erros.forEach { print($0) } }
    let t = placar["total"] ?? (0, 0, 0, 0)
    return Double(t.vp) / Double(max(1, t.vp + t.fp)) >= minimaP && Double(t.vp) / Double(max(1, t.vp + t.fn)) >= minimoR
}
