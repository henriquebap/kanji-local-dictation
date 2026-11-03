import SwiftUI

struct AjustesView: View {
    var body: some View {
        TabView {
            Tab("Geral", systemImage: "gearshape") { GeralView() }
            Tab("Correção", systemImage: "text.badge.checkmark") { CorrecaoView() }
            Tab("Histórico", systemImage: "clock.arrow.circlepath") { HistoricoAjustesView() }
        }
        .frame(width: 580, height: 560)
    }
}

private struct GeralView: View {
    @AppStorage(Ajustes.idioma) private var idioma = "pt_BR"
    @AppStorage(Ajustes.modoSegurar) private var modoSegurar = false
    @AppStorage(Ajustes.sons) private var sons = true
    @AppStorage(Ajustes.colarSozinho) private var colarSozinho = true
    @AppStorage(Ajustes.misturarIngles) private var misturarIngles = true
    @AppStorage(Ajustes.escreverAoVivo) private var escreverAoVivo = false

    var body: some View {
        Form {
            Section("Atalhos globais") {
                LabeledContent("Começar e parar o ditado") { CampoDeAtalho(gravador: .ditar) }
                LabeledContent("Abrir o Kanji") { CampoDeAtalho(gravador: .abrir) }
                Picker("Modo do ditado", selection: $modoSegurar) {
                    Text("Tocar para começar e parar").tag(false)
                    Text("Segurar enquanto fala").tag(true)
                }
            }
            Section("Fala") {
                Picker("Idioma", selection: $idioma) {
                    ForEach(Ajustes.idiomas, id: \.id) { Text($0.nome).tag($0.id) }
                }
                if idioma.hasPrefix("pt") {
                    Toggle("Bilíngue: reconhecer inglês junto com o português", isOn: $misturarIngles)
                }
                Toggle("Sons de início, fim e erro", isOn: $sons)
            }
            Section {
                Toggle("Escrever direto no campo de texto selecionado", isOn: $colarSozinho)
                Toggle("Escrever enquanto você fala", isOn: $escreverAoVivo)
                if colarSozinho && !Area.temAcessibilidade() {
                    LabeledContent("Precisa de permissão de Acessibilidade") {
                        Button("Abrir Ajustes") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
            } footer: {
                Text(escreverAoVivo
                     ? "O texto aparece no campo enquanto você fala, revisado pelo modelo do Mac. Sem campo selecionado, ele aparece no painel e é colado no fim."
                     : "Durante a fala o painel mostra só a onda. Ao parar, o texto revisado pela nuvem entra de uma vez no campo (com o modelo do Mac, o ditado escreve ao vivo).")
            }
        }
        .formStyle(.grouped)
    }
}

private struct CorrecaoView: View {
    @AppStorage(Ajustes.corrigir) private var corrigir = true
    @AppStorage(Ajustes.instrucoes) private var instrucoes = Ajustes.instrucoesPadrao
    @AppStorage(Ajustes.glossario) private var glossario = Ajustes.glossarioPadrao
    @Bindable private var nuvem = ConfigDaNuvem.shared

    var body: some View {
        Form {
            Section {
                Picker("Quem revisa o ditado", selection: $nuvem.provedor) {
                    ForEach(Provedor.allCases) { Text($0.nome).tag($0) }
                }
                if nuvem.provedor != .apple { ContaDaNuvem(nuvem: nuvem) }
            } header: {
                Text("Revisão")
            } footer: {
                Text(nuvem.provedor == .apple
                     ? "O modelo do Mac (Apple Intelligence, ~3B) roda sem internet e sem custo, mas é pequeno: corrige palavras e pontuação trecho a trecho, e não entende o texto inteiro. Ele melhora com o glossário que aprende (abaixo). Para listas na ordem pedida e termos errados pelo contexto, use um modelo da nuvem com a sua chave."
                     : "Ao parar, o texto do ditado vai para \(nuvem.provedor.comArtigo) com a sua chave (o áudio nunca sai do Mac). Cada termo que ele corrige ensina o glossário local. Sem chave, rede ou crédito, o texto fica só com as correções locais e o painel avisa.")
            }
            Section {
                if nuvem.aprendidos.isEmpty {
                    Text("Nada ainda. Quando a revisão da nuvem troca o mesmo termo duas vezes (\"Cláudio\" → Claude), ele aparece aqui.")
                        .foregroundStyle(.secondary)
                }
                ForEach(nuvem.aprendidos, id: \.self) { termo in
                    HStack {
                        Text(termo)
                        Spacer()
                        Button("Esquecer", systemImage: "xmark.circle.fill") { nuvem.esquecer(termo) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Aprendido com a revisão")
            } footer: {
                Text("Valem como o glossário abaixo, também sem internet. Ficam só neste Mac.")
            }
            Section {
                Toggle("Ajustar o texto com o modelo local da Apple", isOn: $corrigir)
                if !Correcao.disponivel {
                    Text("Apple Intelligence indisponível neste Mac: o texto sai como foi transcrito.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                TextField("Palavras", text: $glossario, axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Text("Palavras que você usa")
            } footer: {
                Text("Separadas por vírgula. Quando a transcrição erra algo parecido (\"Cláudio\", \"superbase\"), troca por estas.")
            }
            Section {
                TextEditor(text: $instrucoes)
                    .font(.body.monospaced())
                    .frame(minHeight: 140)
                    .disabled(!corrigir)
            } header: {
                Text("Estilo de escrita")
            } footer: {
                HStack {
                    Text("Poucas regras e diretas: o modelo é pequeno. Listas e pausas já são tratadas.")
                    Spacer()
                    Button("Restaurar padrão") { instrucoes = Ajustes.instrucoesPadrao }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { nuvem.atualizarAprendidos() }  // ditados feitos com os Ajustes abertos ensinam termos novos
    }
}

private struct HistoricoAjustesView: View {
    @Environment(Historico.self) private var historico
    @AppStorage(Ajustes.historicoClipboard) private var clipboard = true

    var body: some View {
        Form {
            Section {
                Toggle("Guardar tudo que for copiado", isOn: $clipboard)
                    .onChange(of: clipboard) { _, ligado in historico.monitorar(ligado) }
            } footer: {
                Text("Itens marcados como senha por gerenciadores (1Password, Bitwarden, Chaves) são ignorados. Tudo fica só neste Mac.")
            }
            Section {
                LabeledContent("Itens guardados", value: "\(historico.entradas.count)")
                Button("Apagar histórico…", role: .destructive) {
                    if confirmarApagar() { historico.limpar() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func confirmarApagar() -> Bool {
        let alerta = NSAlert()
        alerta.messageText = "Apagar todo o histórico?"
        alerta.informativeText = "Ditados e itens copiados serão removidos deste Mac. Não dá para desfazer."
        alerta.alertStyle = .warning
        alerta.addButton(withTitle: "Apagar").hasDestructiveAction = true
        alerta.addButton(withTitle: "Cancelar")
        return alerta.runModal() == .alertFirstButtonReturn
    }
}

/// Chave, modelo e endereço do provedor escolhido.
private struct ContaDaNuvem: View {
    @Bindable var nuvem: ConfigDaNuvem

    var body: some View {
        if nuvem.provedor == .personalizado {
            TextField("Endereço da API (https)", text: $nuvem.endereco, prompt: Text("https://…/v1"))
        }
        TextField("Modelo", text: $nuvem.modelo, prompt: Text(nuvem.provedor.modeloPadrao.isEmpty ? "nome do modelo" : nuvem.provedor.modeloPadrao))
        if nuvem.salva {
            HStack {
                Label("Chave salva no Keychain", systemImage: "key.fill")
                Spacer()
                Button("Testar") { nuvem.testar() }.disabled(nuvem.testando)
                Button("Remover", role: .destructive) { nuvem.remover() }
            }
        } else {
            HStack {
                SecureField("Chave da API", text: $nuvem.digitada)
                Button("Salvar") { nuvem.salvar() }.disabled(nuvem.digitada.isEmpty)
            }
        }
        if nuvem.testando { ProgressView().controlSize(.small) }
        if !nuvem.status.isEmpty { Text(nuvem.status).foregroundStyle(.secondary) }
    }
}

/// Estado da revisão na nuvem nos Ajustes (sem a macro @State, que exige o Xcode completo).
@MainActor @Observable
private final class ConfigDaNuvem {
    static let shared = ConfigDaNuvem()

    var provedor = Nuvem.escolhido {
        didSet {
            UserDefaults.standard.set(provedor.rawValue, forKey: Ajustes.provedor)
            recarregar()
        }
    }
    var modelo = "" {
        // O padrão não é gravado: se ele mudar numa versão nova do Kanji, quem não escolheu outro acompanha.
        didSet { UserDefaults.standard.set(modelo == provedor.modeloPadrao ? "" : modelo, forKey: Nuvem.chaveDoModelo(provedor)) }
    }
    var endereco = UserDefaults.standard.string(forKey: Ajustes.enderecoPersonalizado) ?? "" {
        didSet { UserDefaults.standard.set(endereco, forKey: Ajustes.enderecoPersonalizado) }
    }
    var digitada = ""
    private(set) var salva = false
    private(set) var status = ""
    private(set) var testando = false
    private(set) var aprendidos = Aprendizado.termos

    init() { recarregar() }

    private func recarregar() {
        modelo = Nuvem.modelo(provedor)
        salva = Chaveiro.existe(provedor)
        (digitada, status, testando) = ("", "", false)
        aprendidos = Aprendizado.termos
    }

    func salvar() {
        let limpa = digitada.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpa.contains(where: \.isWhitespace) else { return status = "A chave não pode ter espaços." }
        if provedor == .anthropic, !limpa.hasPrefix("sk-ant-") { return status = "A chave da API da Anthropic começa com sk-ant-." }
        guard Chaveiro.salvar(limpa, provedor) else { return status = "Não consegui guardar a chave no Keychain." }
        digitada = ""
        salva = true
        testar()
    }

    func testar() {
        guard let chave = Chaveiro.ler(provedor) else { return }
        testando = true
        status = ""
        let alvo = provedor
        Task {
            let resultado = await Nuvem.testar(alvo, chave: chave)
            guard alvo == provedor else { return }  // trocou de provedor no meio do teste
            status = resultado
            testando = false
        }
    }

    func remover() {
        Chaveiro.apagar(provedor)
        salva = false
        status = ""
    }

    func esquecer(_ termo: String) {
        Aprendizado.esquecer(termo)
        atualizarAprendidos()
    }

    func atualizarAprendidos() {
        aprendidos = Aprendizado.termos
    }
}
