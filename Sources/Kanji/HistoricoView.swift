import SwiftUI

/// ponytail: estado da tela numa classe @Observable em vez de @State (macro do SwiftUI só vem com o Xcode).
@MainActor @Observable
final class FiltroHistorico {
    static let shared = FiltroHistorico()
    var busca = ""
    var filtro: Entrada.Tipo?
    var selecao: Entrada.ID?
}

struct HistoricoView: View {
    @Environment(Historico.self) private var historico
    @Bindable private var ui = FiltroHistorico.shared

    private var filtradas: [Entrada] {
        historico.entradas.filter { e in
            (ui.filtro == nil || e.tipo == ui.filtro) && (ui.busca.isEmpty || e.texto.localizedStandardContains(ui.busca))
        }
    }

    var body: some View {
        NavigationSplitView {
            List(filtradas, selection: $ui.selecao) { entrada in
                Linha(entrada: entrada)
                    .contextMenu {
                        Button("Copiar") { Area.copiar(entrada.texto, historico: historico) }
                        Button("Apagar", role: .destructive) { historico.remover([entrada.id]) }
                    }
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 320)
            .overlay {
                if filtradas.isEmpty {
                    ContentUnavailableView(ui.busca.isEmpty ? String(localized: "Nada por aqui ainda") : String(localized: "Sem resultados"),
                                           systemImage: "clock.arrow.circlepath")
                }
            }
        } detail: {
            if let id = ui.selecao, let entrada = historico.entradas.first(where: { $0.id == id }) {
                Detalhe(entrada: entrada)
            } else {
                Inicio()
            }
        }
        .searchable(text: $ui.busca, placement: .sidebar, prompt: "Buscar no histórico")
        .toolbar {
            Picker("Filtro", selection: $ui.filtro) {
                Text("Tudo").tag(Entrada.Tipo?.none)
                Text("Ditados").tag(Entrada.Tipo?.some(.ditado))
                Text("Copiados").tag(Entrada.Tipo?.some(.clipboard))
            }
            .pickerStyle(.segmented)
            Button("Ajustes", systemImage: "gearshape") { Kanji.shared.janelas.mostrarAjustes() }
        }
        .onDeleteCommand { if let id = ui.selecao { historico.remover([id]) } }
    }
}

private struct Linha: View {
    let entrada: Entrada

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entrada.texto).lineLimit(2)
            HStack(spacing: 4) {
                Image(systemName: entrada.tipo == .ditado ? "waveform" : "doc.on.clipboard")
                Text(entrada.data, format: .relative(presentation: .named))
                if let app = entrada.app { Text("· \(app)") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct Detalhe: View {
    @Environment(Historico.self) private var historico
    let entrada: Entrada

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(entrada.texto)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let bruto = entrada.bruto, bruto != entrada.texto {
                    GroupBox("Transcrição original") {
                        Text(bruto)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text("\(entrada.data.formatted(date: .abbreviated, time: .shortened))\(entrada.app.map { " · \($0)" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .toolbar {
            Button("Copiar", systemImage: "doc.on.doc") { Area.copiar(entrada.texto, historico: historico) }
        }
    }
}

/// Tela inicial: como usar e o que falta liberar.
private struct Inicio: View {
    @Environment(Ditado.self) private var ditado

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "waveform")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(.tint)
                .symbolEffect(.variableColor.iterative, isActive: ditado.fase == .gravando)
            VStack(spacing: 6) {
                Text("Aperte \(Acao.ditar.atalho.descricao) em qualquer app e fale")
                    .font(.title2.weight(.semibold))
                Text("Aperte de novo para parar. O texto aparece na hora, é ajustado no próprio Mac e colado onde está o cursor.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            Button(ditado.fase == .gravando ? String(localized: "Parar") : String(localized: "Ditar agora"), systemImage: ditado.fase == .gravando ? "stop.fill" : "mic.fill") {
                ditado.alternar()
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            VStack(alignment: .leading, spacing: 8) {
                Requisito(ok: Correcao.disponivel, texto: "Apple Intelligence ativado",
                          ajuda: "Sem ele o texto sai como foi transcrito.")
                Requisito(ok: Area.temAcessibilidade(), texto: "Permissão de Acessibilidade",
                          ajuda: "Para colar sozinho. Ajustes do Sistema › Privacidade › Acessibilidade.")
            }
            .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct Requisito: View {
    let ok: Bool
    let texto: LocalizedStringKey
    let ajuda: LocalizedStringKey

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(texto)
                if !ok { Text(ajuda).font(.caption).foregroundStyle(.secondary) }
            }
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(ok ? .green : .orange)
        }
    }
}
