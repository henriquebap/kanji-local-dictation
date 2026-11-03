/// Chaves do UserDefaults (lidas via @AppStorage nas views e UserDefaults no controlador).
enum Ajustes {
    static let idioma = "idioma"
    static let modoSegurar = "modoSegurar"
    static let corrigir = "corrigir"
    static let instrucoes = "instrucoes"
    static let sons = "sons"
    static let colarSozinho = "colarSozinho"
    static let historicoClipboard = "historicoClipboard"
    static let misturarIngles = "misturarIngles"
    static let glossario = "glossario"
    static let provedor = "provedor"
    static let enderecoPersonalizado = "enderecoPersonalizado"
    static let viuPrimeirosPassos = "viuPrimeirosPassos"
    static let escreverAoVivo = "escreverAoVivo"

    static var padroes: [String: Any] { [
        idioma: "pt_BR",
        modoSegurar: false,
        corrigir: true,
        instrucoes: instrucoesPadrao,
        sons: true,
        colarSozinho: true,
        historicoClipboard: true,
        misturarIngles: true,
        glossario: glossarioPadrao,
        escreverAoVivo: false,
    ] }

    static let glossarioPadrao = "Claude, Claude Code, LLM, prompt, deploy, commit, pull request, branch, bug, bugado, feature, API, app, backend, frontend, speech to text, running, checking, Supabase, GitHub, Siri"


    /// Estilo de escrita da pessoa. Listas e frases cortadas por pausa são tratadas por regras no código.
    static let instrucoesPadrao = """
        Mantenha o jeito de falar da pessoa (tô, pra, a gente).
        Termos em inglês ficam em inglês.
        """

    static let idiomas: [(id: String, nome: String)] = [
        ("pt_BR", "Português (Brasil)"), ("pt_PT", "Português (Portugal)"),
        ("en_US", "English (US)"), ("es_ES", "Español"),
    ]
}
