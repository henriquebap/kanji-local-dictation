import SwiftUI

/// Linha da lista: quando, quanto tempo e quem falou.
struct LinhaDaTranscricao: View {
    let transcricao: Transcricao

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(transcricao.inicio.formatted(date: .abbreviated, time: .shortened))
            Text(transcricao.turnos().first?.texto ?? "")
                .lineLimit(2)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Image(systemName: "record.circle")
                Text(Self.duracao(transcricao.duracao))
                Text("· \(transcricao.locutores.joined(separator: ", "))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    static func duracao(_ segundos: Double) -> String {
        Duration.seconds(segundos).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
    }
}

/// ponytail: estado da tela numa classe @Observable em vez de @State (macro do SwiftUI só vem com o Xcode).
@MainActor @Observable
final class Renomeacao {
    static let shared = Renomeacao()
    var antigo: String?
    var novo = ""
}

/// Uma sessão inteira: resumo (quando houver) e os turnos com a hora e quem falou.
struct DetalheDaTranscricao: View {
    @Environment(Historico.self) private var historico
    @Bindable private var arquivo = Transcricoes.shared
    @Bindable private var renomeacao = Renomeacao.shared
    let transcricao: Transcricao

    private var andamento: Bool { arquivo.emAndamento(transcricao) }
    private var resumindo: Bool { arquivo.resumindo[transcricao.id] != nil }
    private var analises: [Analise: String] { arquivo.resumos[transcricao.id] ?? [:] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(transcricao.data).font(.title2.weight(.semibold))
                    Text("\(LinhaDaTranscricao.duracao(transcricao.duracao)) · \(transcricao.locutores.joined(separator: ", "))")
                        .foregroundStyle(.secondary)
                    if andamento { Label("Gravando: renomear e apagar ficam para depois de parar", systemImage: "record.circle") }
                }
                acoes
                if let erro = arquivo.erros[transcricao.id] {
                    Label(erro, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                if let analise = arquivo.resumindo[transcricao.id] {
                    let com = Nuvem.pronto?.comArtigo ?? ""
                    ProgressView(analise == .entrevista ? String(localized: "Analisando a entrevista com \(com)…")
                                                        : String(localized: "Resumindo com \(com)…")).controlSize(.small)
                }
                ForEach(Analise.allCases.reversed(), id: \.self) { analise in  // o feedback, quando houver, vem primeiro
                    if let texto = analises[analise] {
                        GroupBox {
                            TextoMarkdown(texto: texto)
                        } label: {
                            HStack {
                                Text(analise == .entrevista ? String(localized: "Feedback da entrevista") : String(localized: "Resumo"))
                                Spacer()
                                Button("Copiar", systemImage: "doc.on.doc") { Area.copiar(texto, historico: historico) }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                ForEach(Array(transcricao.turnos().enumerated()), id: \.offset) { _, turno in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(Transcricao.relogio(turno.inicio)) · \(turno.quem)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(turno.texto)
                    }
                }
                .textSelection(.enabled)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert(String(localized: "Renomear \(renomeacao.antigo ?? "")"),
               isPresented: Binding(get: { renomeacao.antigo != nil }, set: { if !$0 { renomeacao.antigo = nil } })) {
            TextField("Nome", text: $renomeacao.novo)
            Button("Renomear") {
                if let antigo = renomeacao.antigo { _ = arquivo.renomear(transcricao, antigo, para: renomeacao.novo) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Muda em todos os trechos e nos arquivos .md e .json.")
        }
    }

    /// Fora da barra da janela: com o seletor de seções nela, os botões iam parar escondidos no menu "»".
    private var acoes: some View {
        HStack {
            Button(analises[.resumo] == nil ? String(localized: "Resumir") : String(localized: "Resumir de novo"),
                   systemImage: "sparkles") {
                Task { await arquivo.resumir(transcricao) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(resumindo)
            Button("Feedback", systemImage: "person.fill.checkmark") {
                Task { await arquivo.resumir(transcricao, .entrevista) }
            }
            .help("Feedback de entrevista: pontos fortes e o que melhorar nas suas respostas (as do Você)")
            .disabled(resumindo)
            Button("Copiar", systemImage: "doc.on.doc") { Area.copiar(transcricao.markdown(), historico: historico) }
            Menu("Renomear", systemImage: "person.text.rectangle") {
                ForEach(transcricao.locutores, id: \.self) { quem in
                    Button(quem) { (renomeacao.antigo, renomeacao.novo) = (quem, quem) }
                }
            }
            .fixedSize()
            .disabled(andamento)
            // Só o ícone: com o botão do feedback, os rótulos não cabiam e todos saíam cortados ("Resumi…").
            Button("Mostrar no Finder", systemImage: "folder") { arquivo.mostrarNoFinder(transcricao) }
                .labelStyle(.iconOnly)
                .help("Mostrar no Finder")
            Button("Mover para o Lixo", systemImage: "trash") { arquivo.apagar(transcricao) }
                .labelStyle(.iconOnly)
                .help("Mover para o Lixo")
                .disabled(andamento || resumindo)
        }
    }
}

/// O resumo vem em Markdown simples (títulos, tópicos, negrito). O `Text` do SwiftUI só entende o que fica dentro
/// da linha, então cada linha vira um `Text`: título com fonte maior, tópico com "•".
struct TextoMarkdown: View {
    let texto: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(texto.split(separator: "\n").enumerated()), id: \.offset) { _, linha in
                if linha.hasPrefix("#") {
                    Text(linha.drop { $0 == "#" || $0 == " " })
                        .font(linha.hasPrefix("# ") ? .title3.weight(.semibold) : .headline)
                        .padding(.top, 4)
                } else {
                    Text(Self.linha(linha))
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func linha(_ linha: Substring) -> AttributedString {
        let texto = linha.hasPrefix("- ") || linha.hasPrefix("* ") ? "• " + linha.dropFirst(2) : String(linha)
        let opcoes = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: texto, options: opcoes)) ?? AttributedString(texto)
    }
}
