import SwiftUI

@main
struct KanjiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        UserDefaults.standard.register(defaults: Ajustes.padroes)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(Kanji.shared.ditado)
                .environment(Kanji.shared.historico)
        } label: {
            Image(systemName: Kanji.shared.ditado.icone)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Ajustes…") { Kanji.shared.janelas.mostrarAjustes() }
                    .keyboardShortcut(",")
            }
            CommandMenu("Ditado") {
                Button("Começar ou parar ditado") { Kanji.shared.ditado.alternar() }
                Button("Mostrar histórico") { Kanji.shared.janelas.mostrarPrincipal() }
                    .keyboardShortcut("y")  // mesmo atalho do histórico no Safari; ⌘H é "Ocultar" no macOS
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Kanji.shared.iniciar()
    }

    /// Clique no ícone do Dock com a janela fechada: abre de novo.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { Kanji.shared.janelas.mostrarPrincipal() }
        return true
    }
}

/// Raiz de composição: cria os objetos uma vez e liga os atalhos globais.
@MainActor
final class Kanji {
    static let shared = Kanji()

    let historico = Historico()
    let ditado: Ditado
    let janelas: Janelas

    private init() {
        ditado = Ditado(historico: historico)
        janelas = Janelas(historico: historico, ditado: ditado)
    }

    func iniciar() {
        historico.monitorar(UserDefaults.standard.bool(forKey: Ajustes.historicoClipboard))
        let atalhos = AtalhoGlobal.shared
        atalhos.aoPressionar = { [ditado, janelas] acao in
            switch acao {
            case .ditar: ditado.teclaDesceu()
            case .abrir: janelas.mostrarPrincipal()
            case .cancelar: ditado.cancelar()
            }
        }
        atalhos.aoSoltar = { [ditado] acao in
            if acao == .ditar { ditado.teclaSubiu() }
        }
        atalhos.registrar(.ditar)
        atalhos.registrar(.abrir)
        // Primeira vez: a janela de primeiros passos explica e pede cada permissão no momento certo.
        guard UserDefaults.standard.bool(forKey: Ajustes.viuPrimeirosPassos) else { return janelas.mostrarPrimeirosPassos() }
        janelas.mostrarPrincipal()
        // Sem Acessibilidade não dá para escrever no campo em foco: o aviso do sistema cria a entrada certa
        // para a assinatura atual (uma entrada antiga, de outra assinatura, não vale).
        if !Area.temAcessibilidade(pedir: true) { registro.notice("Acessibilidade pendente: aviso do sistema exibido") }
    }
}

struct MenuView: View {
    @Environment(Ditado.self) private var ditado
    @Environment(Historico.self) private var historico

    var body: some View {
        Button(ditado.fase == .gravando ? "Parar e colar" : "Começar a ditar  (\(Acao.ditar.atalho.descricao))") {
            ditado.alternar()
        }
        .disabled(ditado.fase == .preparando || ditado.fase == .ajustando)

        Divider()
        Section("Recentes") {
            ForEach(historico.entradas.prefix(5)) { entrada in
                Button(entrada.texto.prefix(60) + (entrada.texto.count > 60 ? "…" : "")) {
                    Area.copiar(entrada.texto, historico: historico)
                }
            }
        }

        Divider()
        Button("Abrir Kanji  (\(Acao.abrir.atalho.descricao))") { Kanji.shared.janelas.mostrarPrincipal() }
        Button("Ajustes…") { Kanji.shared.janelas.mostrarAjustes() }
        Button("Primeiros passos…") { Kanji.shared.janelas.mostrarPrimeirosPassos() }
        Divider()
        Button("Sair do Kanji") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
