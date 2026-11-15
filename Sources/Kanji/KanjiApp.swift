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
                .environment(Kanji.shared.sessao)
        } label: {
            // Ditado tem prioridade no ícone; fora dele, a sessão do Mac gravando aparece como um ponto de gravação.
            Image(systemName: Kanji.shared.sessao.ativa && !Kanji.shared.ditado.ativo ? "record.circle" : Kanji.shared.ditado.icone)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Ajustes…") { Kanji.shared.janelas.mostrarAjustes() }
                    .keyboardShortcut(",")
            }
            CommandMenu("Ditado") {
                Button("Começar ou parar ditado") { Kanji.shared.ditado.alternar() }
                Button("Transcrever ou parar o áudio do Mac") { Kanji.shared.sessao.alternar() }
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
    let sessao = SessaoDoMac()
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
            case .transcrever: Kanji.shared.sessao.alternar()
            }
        }
        atalhos.aoSoltar = { [ditado] acao in
            if acao == .ditar { ditado.teclaSubiu() }
        }
        atalhos.registrar(.ditar)
        atalhos.registrar(.abrir)
        atalhos.registrar(.transcrever)
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
    @Environment(SessaoDoMac.self) private var sessao

    var body: some View {
        Button(ditado.fase == .gravando ? String(localized: "Parar e colar")
               : String(localized: "Começar a ditar  (\(Acao.ditar.atalho.descricao))")) {
            ditado.alternar()
        }
        .disabled(ditado.fase == .preparando || ditado.fase == .ajustando)

        Divider()
        Button(sessao.fase == .gravando
               ? String(localized: "Parar a transcrição do Mac (\(String(sessao.trechos)) trechos)")
               : String(localized: "Transcrever o áudio do Mac  (\(Acao.transcrever.atalho.descricao))")) {
            sessao.alternar()
        }
        .disabled(sessao.fase == .preparando || sessao.fase == .finalizando)
        if case .erro(let mensagem) = sessao.fase { Text(mensagem) }
        Button("Abrir transcrições") { sessao.abrirPasta() }

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
