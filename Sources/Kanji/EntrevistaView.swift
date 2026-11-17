import AppKit
import SwiftUI

/// ponytail: estado da aba numa classe @Observable em vez de @State (macro do SwiftUI só vem com o Xcode).
@MainActor @Observable
final class PerguntaDeTeste {
    static let shared = PerguntaDeTeste()
    var pergunta = ""
    private(set) var resposta: String?
    private(set) var erro: String?
    private(set) var resumoDaPasta: String?
    private(set) var perguntando = false

    var pasta: URL? {
        UserDefaults.standard.string(forKey: Ajustes.pastaDasNotas).map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    func escolherPasta() {
        let painel = NSOpenPanel()
        (painel.canChooseDirectories, painel.canChooseFiles) = (true, false)
        painel.prompt = String(localized: "Usar esta pasta")
        guard painel.runModal() == .OK, let url = painel.url else { return }
        UserDefaults.standard.set(url.path(percentEncoded: false), forKey: Ajustes.pastaDasNotas)
        conferirPasta()
    }

    /// Lê de novo a cada vez: a pasta é a fonte, e a pessoa pode ter editado uma nota agora há pouco.
    @discardableResult
    func conferirPasta() -> String? {
        guard let pasta else { return nil }
        do {
            let (pacote, quantas) = try Notas.ler(pasta)
            resumoDaPasta = String(localized: "\(String(quantas)) notas, \(String(pacote.count / 1000)) mil caracteres")  // String: um Int viraria %lld na chave
            erro = pacote.count > Notas.limite ? String(localized: "As notas passam do limite. Escolha uma pasta só com as notas de carreira.") : nil
            return pacote
        } catch {
            registro.error("notas ilegíveis: \(error.localizedDescription, privacy: .private)")
            resumoDaPasta = nil
            erro = String(localized: "Não consegui ler as notas: \(error.localizedDescription)")
            return nil
        }
    }

    func perguntar() async {
        let pergunta = pergunta.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !perguntando, !pergunta.isEmpty, let notas = conferirPasta(), erro == nil else { return }
        perguntando = true
        defer { perguntando = false }
        do {
            resposta = try await Nuvem.perguntar(pergunta, notas: notas)
        } catch {
            registro.error("pergunta às notas falhou: \(error.localizedDescription, privacy: .private)")  // pode citar as notas
            erro = error.localizedDescription
        }
    }
}

/// Modo entrevista, passo 1: escolher as notas e testar uma pergunta antes de usar numa entrevista de verdade.
struct EntrevistaView: View {
    @Bindable private var estado = PerguntaDeTeste.shared
    @AppStorage(Ajustes.sugerirNaEntrevista) private var sugerir = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Pasta") {
                    HStack {
                        Text(estado.pasta?.lastPathComponent ?? String(localized: "nenhuma"))
                            .foregroundStyle(.secondary)
                        Button("Escolher…") { estado.escolherPasta() }
                    }
                }
                if let resumo = estado.resumoDaPasta { LabeledContent("Lidas", value: resumo) }
            } header: {
                Text("Notas de carreira")
            } footer: {
                Text("Uma pasta de Markdown, como um cofre do Obsidian. Ficam de fora as pastas ocultas, as começadas por _ e as chamadas arquivo ou archive. O Kanji lê na hora de perguntar e não guarda cópia; só o texto das notas e a pergunta vão para o provedor da nuvem.")
            }
            Section {
                Toggle("Sugerir respostas durante a transcrição do Mac", isOn: $sugerir)
                    .disabled(estado.pasta == nil)
                LabeledContent("Pedir tópicos agora") { CampoDeAtalho(gravador: .perguntar) }
            } header: {
                Text("Ao vivo")
            } footer: {
                Text("Quando o entrevistador pergunta, um painel no canto da tela mostra tópicos tirados das notas. O painel pede ao macOS para ficar fora do compartilhamento de tela: confira numa chamada de teste. Se uma pergunta passar sem painel, use o atalho. Vale a partir da próxima transcrição.")
            }
            Section("Testar uma pergunta") {
                TextField("Pergunta do entrevistador", text: $estado.pergunta, axis: .vertical)
                    .onSubmit { Task { await estado.perguntar() } }
                HStack {
                    Button("Perguntar às notas", systemImage: "sparkles") { Task { await estado.perguntar() } }
                        .disabled(estado.perguntando || estado.pasta == nil || estado.pergunta.isEmpty)
                    if estado.perguntando { ProgressView().controlSize(.small) }
                }
                if let erro = estado.erro {
                    Label(erro, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                if let resposta = estado.resposta { TextoMarkdown(texto: resposta) }
            }
        }
        .formStyle(.grouped)
        .onAppear { estado.conferirPasta() }
    }
}
