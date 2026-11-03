import AppKit
import SwiftUI

/// Janelas criadas em AppKit para poderem ser abertas de qualquer lugar (atalho global, Dock, menu).
@MainActor
final class Janelas {
    private let historico: Historico
    private let ditado: Ditado
    private var principal: NSWindow?
    private var ajustes: NSWindow?
    private var primeirosPassos: NSWindow?

    init(historico: Historico, ditado: Ditado) {
        self.historico = historico
        self.ditado = ditado
    }

    func mostrarPrincipal() {
        let janela = principal ?? criar(
            titulo: "Kanji",
            conteudo: HistoricoView().environment(historico).environment(ditado),
            estilo: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            tamanho: NSSize(width: 860, height: 560),
            nome: "principal")
        principal = janela
        trazerParaFrente(janela)
    }

    func mostrarAjustes() {
        let janela = ajustes ?? criar(
            titulo: "Ajustes do Kanji",
            conteudo: AjustesView().environment(historico),
            estilo: [.titled, .closable],
            tamanho: NSSize(width: 560, height: 460),
            nome: "ajustes")
        ajustes = janela
        trazerParaFrente(janela)
    }

    func mostrarPrimeirosPassos() {
        let janela = primeirosPassos ?? criar(
            titulo: "Primeiros passos",
            conteudo: PrimeirosPassosView { [weak self] in
                UserDefaults.standard.set(true, forKey: Ajustes.viuPrimeirosPassos)
                self?.primeirosPassos?.close()
                self?.mostrarPrincipal()
            },
            estilo: [.titled, .closable],
            tamanho: NSSize(width: 560, height: 520),
            nome: "primeirosPassos")
        primeirosPassos = janela
        trazerParaFrente(janela)
    }

    private func criar(titulo: String, conteudo: some View, estilo: NSWindow.StyleMask,
                       tamanho: NSSize, nome: String) -> NSWindow {
        let janela = NSWindow(contentRect: NSRect(origin: .zero, size: tamanho), styleMask: estilo,
                              backing: .buffered, defer: false)
        janela.title = titulo
        janela.contentView = NSHostingView(rootView: conteudo)
        janela.isReleasedWhenClosed = false
        janela.center()
        janela.setFrameAutosaveName(nome)  // lembra posição e tamanho entre aberturas
        return janela
    }

    private func trazerParaFrente(_ janela: NSWindow) {
        NSApp.activate()
        janela.makeKeyAndOrderFront(nil)
    }
}
