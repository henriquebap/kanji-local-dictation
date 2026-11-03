import AppKit
import FoundationModels

@MainActor
enum Correcao {
    /// Guardrail próprio para transformar texto do usuário: o padrão recusava frases inofensivas
    /// ("Response may contain sensitive or unsafe content" em trechos sobre mercado e carros).
    private static let modelo = SystemLanguageModel(guardrails: .permissiveContentTransformations)

    static var disponivel: Bool {
        if case .available = modelo.availability { true } else { false }
    }

    /// Regras fixas da revisão em tempo real; o estilo da pessoa (Ajustes) vem depois delas.
    private static let regras = """
        Você revisa um ditado por voz em tempo real, um trecho por vez, em português do Brasil com termos em inglês.
        Corrija erros de transcrição, acentuação e pontuação do trecho novo. O texto anterior serve só de contexto.
        Nunca traduza o que foi dito em inglês. Não acrescente nem resuma nada.
        """

    // ponytail: esquema montado à mão; @Generable faria o mesmo, mas o plugin de macros exige Xcode completo
    private static let esquema = try? GenerationSchema(
        root: DynamicGenerationSchema(name: "Revisao", properties: [
            .init(name: "trecho", description: "o trecho novo, revisado", schema: .init(type: String.self)),
        ]),
        dependencies: [])

    /// Pré-carrega o modelo ao começar a gravar: o primeiro trecho sai em ~0,5 s em vez de ~2 s.
    static func aquecer() {
        guard disponivel else { return }
        LanguageModelSession(model: modelo, instructions: regras).prewarm()
    }

    /// Revisa um trecho com o modelo local. O esquema guiado impede que o modelo repita o texto anterior
    /// ou comente (visto nos testes com texto livre). Se ele não for fiel ao trecho, devolve o trecho como veio.
    static func revisarTrecho(_ trecho: String, anterior: String, estilo: String, glossario: [String]) async -> String {
        guard !trecho.isEmpty, disponivel, let esquema else { return trecho }
        // Trecho falado em inglês: o modelo de 3B só sabe traduzir, nunca corrigir. Nem vale chamar.
        let ditas = palavras(trecho).filter { $0.count >= 3 }
        guard Double(ditas.filter(emIngles).count) < Double(ditas.count) * 0.4 else { return trecho }
        let termos = glossario.isEmpty ? "" : "\nGrafias corretas de palavras que a pessoa usa: \(glossario.joined(separator: ", "))."
        do {
            let session = LanguageModelSession(model: modelo, instructions: regras + "\n" + estilo + termos)
            let prompt = "Texto anterior:\n\(anterior.isEmpty ? "(início)" : anterior)\n\nTrecho novo:\n\(trecho)"
            // Greedy: o mesmo trecho sempre gera a mesma revisão (com amostragem, o 3B oscila muito).
            // Teto de tokens: com greedy o modelo às vezes entra em loop e gera até estourar o contexto (8192 tokens,
            // ~2 min travando a fila inteira). A revisão nunca precisa ser muito maior que o trecho.
            let opcoes = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: trecho.count / 2 + 64)
            let resposta = try await session.respond(to: prompt, schema: esquema, options: opcoes)
            let revisado = try resposta.content.value(String.self, forProperty: "trecho")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard fiel(revisado, a: trecho, glossario: glossario) else {
                registro.notice("revisão de trecho descartada: o modelo traduziu ou cortou")
                return trecho
            }
            return revisado
        } catch {
            registro.error("revisão de trecho falhou: \(error, privacy: .private)")  // o erro pode citar o trecho
            return trecho
        }
    }

    /// O modelo de 3B às vezes traduz o inglês, resume, ou "responde" ao texto em vez de corrigir.
    /// Confere se as palavras de conteúdo do ditado continuam lá; listas podem trocar "primeiro" por "1.".
    /// Cada termo do glossário que entrou na correção ("bees base" → "Supabase") compensa até duas palavras trocadas.
    static func fiel(_ corrigido: String, a bruto: String, glossario: [String] = []) -> Bool {
        let razao = Double(corrigido.count) / Double(max(bruto.count, 1))
        guard !corrigido.isEmpty, (0.5...1.6).contains(razao) else { return false }

        let saida = Set(palavras(corrigido))
        let termos = glossario.map { $0.lowercased() }
            .filter { corrigido.lowercased().contains($0) && !bruto.lowercased().contains($0) }.count
        // Inglês é o que o modelo mais traduz ("My name is Henrique" → "Meu nome é Henrique"), e em trecho curto
        // a tolerância abaixo deixava passar. Toda palavra em inglês tem de continuar lá, salvo a que virou termo do glossário.
        let ingles = palavras(bruto).filter { $0.count >= 3 && emIngles($0) }
        guard ingles.filter({ !saida.contains($0) }).count <= termos else { return false }

        let conteudo = palavras(bruto).filter { $0.count >= 4 && !Self.numerais.contains($0) }
        guard !conteudo.isEmpty else { return true }
        let trocas = 2 * termos
        let mantidas = conteudo.filter { saida.contains($0) }.count + trocas
        // Corrigir é trocar palavras, não acrescentar: "tá meio" → "tá meio bugado" ou "database" → "banco de dados"
        // trazem mais palavras novas do que as que sumiram.
        let entrada = Set(palavras(bruto))
        let novas = palavras(corrigido).filter { $0.count >= 3 && !entrada.contains($0) }.count
        let sumidas = palavras(bruto).filter { $0.count >= 3 && !saida.contains($0) }.count
        // Em trecho curto, uma palavra trocada já derrubaria a proporção: aceita perder uma.
        return (Double(mantidas) / Double(conteudo.count) >= 0.7 || conteudo.count - mantidas <= 1)
            && novas <= sumidas
    }

    private static let numerais: Set<String> = [
        "primeiro", "primeira", "segundo", "segunda", "terceiro", "terceira", "quarto", "quarta", "quinto", "quinta",
        "dois", "duas", "três", "quatro", "cinco", "seis", "sete", "oito", "nove", "item", "itens",
    ]

    private static func palavras(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func emIngles(_ palavra: String) -> Bool {
        Fusao.existe(palavra, "en") && !Fusao.existe(palavra, "pt_BR")
    }
}
