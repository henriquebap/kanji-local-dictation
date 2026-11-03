import AppKit
import SwiftUI

/// Painel flutuante que não rouba o foco: o cursor continua no app em que o texto vai ser colado.
@MainActor
final class PainelFlutuante {
    static let largura: CGFloat = 480
    private let janela: NSPanel

    init(ditado: Ditado) {
        janela = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.largura, height: 120),
                         styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        janela.isFloatingPanel = true
        janela.level = .statusBar
        janela.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        janela.backgroundColor = .clear
        janela.isOpaque = false
        janela.hasShadow = false  // a sombra vem do SwiftUI, que respeita o canto arredondado
        janela.hidesOnDeactivate = false
        janela.isMovableByWindowBackground = true
        let host = NSHostingView(rootView: PainelView(ditado: ditado) { [weak self] altura in
            self?.ajustar(altura: altura)
        })
        host.sizingOptions = []  // o tamanho da janela é decidido aqui, não pelo SwiftUI
        janela.contentView = host
    }

    func mostrar() {
        posicionar(altura: janela.frame.height)
        janela.orderFrontRegardless()
    }

    func esconder() {
        janela.orderOut(nil)
    }

    /// O SwiftUI informa a altura do conteúdo; o painel cresce para cima, preso à base da tela.
    private func ajustar(altura: CGFloat) {
        guard abs(altura - janela.frame.height) > 0.5 else { return }
        // Fora do ciclo de layout atual: redimensionar durante o layout gera recursão no AppKit.
        Task { @MainActor in posicionar(altura: altura) }
    }

    private func posicionar(altura: CGFloat) {
        let mouse = NSEvent.mouseLocation
        let tela = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let area = tela?.visibleFrame else { return }
        janela.setFrame(NSRect(x: area.midX - Self.largura / 2, y: area.minY + 64, width: Self.largura, height: altura),
                        display: true)
    }
}

struct PainelView: View {
    let ditado: Ditado
    let aoMudarAltura: (CGFloat) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Cabecalho(ditado: ditado)
            Corpo(ditado: ditado)
            Rodape(ditado: ditado)
        }
        .padding(16)
        .frame(width: PainelFlutuante.largura - 24, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .padding(12)  // espaço para a sombra do vidro não ser cortada
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { aoMudarAltura($0) }
        .animation(.smooth(duration: 0.25), value: ditado.fase)
    }
}

private struct Cabecalho: View {
    let ditado: Ditado

    var body: some View {
        HStack(spacing: 12) {
            switch ditado.fase {
            case .preparando:
                ProgressView().controlSize(.small)
                Text("Ligando o microfone…").foregroundStyle(.secondary)
                Spacer()
            case .gravando:
                Image(systemName: "circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse)
                Onda(niveis: ditado.niveis)
                Text(ditado.inicio, style: .timer)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button("Parar", systemImage: "stop.fill") { ditado.parar() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glassProminent)
                    .tint(.red)
            case .ajustando:
                Image(systemName: "sparkles")
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse)
                Text(ditado.revisandoCom.map { String(localized: "Revisando com \($0.comArtigo)…") }
                     ?? String(localized: "Revisando o último trecho…"))
                    .foregroundStyle(.secondary)
                Spacer()
                ProgressView().controlSize(.small)
            case .pronto(let colado):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(colado ? (ditado.escrevendoEm.map { String(localized: "Pronto no \($0)") } ?? String(localized: "Colado"))
                     : String(localized: "Copiado. Use ⌘V para colar"))
                    .foregroundStyle(.secondary)
                Spacer()
                if !colado {
                    Button("Copiar de novo", systemImage: "doc.on.doc") { ditado.copiarResultado() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                }
            case .erro(let mensagem):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(mensagem).fixedSize(horizontal: false, vertical: true)
                Spacer()
            case .parado:
                EmptyView()
            }
        }
        .font(.callout)
        .frame(minHeight: 30)
    }
}

/// Texto ao vivo: o trecho firme em cor normal, o rascunho do modelo em cinza.
/// Com campo em foco, o painel mostra só o que está sendo ouvido (o texto revisado aparece no campo).
/// Sem campo, mostra o texto revisado e, em cinza, o que ainda está sendo ouvido.
private struct Corpo: View {
    let ditado: Ditado

    var body: some View {
        switch ditado.fase {
        case .gravando where !ditado.aoVivo:
            EmptyView()  // só a onda: o texto entra pronto quando a pessoa para
        case .gravando where ditado.escrevendoEm != nil:
            Text(ditado.rascunho.isEmpty ? String(localized: "Ouvindo…") : ditado.rascunho)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
        case .gravando where ditado.revisado.isEmpty && ditado.rascunho.isEmpty:
            Text("Pode falar…").foregroundStyle(.tertiary)
        case .gravando:
            Text("\(ditado.revisado) \(Text(ditado.rascunho).foregroundStyle(.secondary))")
                .lineLimit(5)
                .truncationMode(.head)
        case .ajustando, .pronto:
            if ditado.escrevendoEm == nil {
                Text(ditado.revisado)
                    .lineLimit(6)
                    .truncationMode(.head)
                    .textSelection(.enabled)
            }
        case .parado, .preparando, .erro:
            EmptyView()
        }
    }
}

private struct Rodape: View {
    let ditado: Ditado

    var body: some View {
        if case .pronto = ditado.fase, let aviso = ditado.aviso {
            Text(aviso)
                .font(.caption)
                .foregroundStyle(.orange)
        } else if ditado.fase == .gravando || ditado.fase == .preparando {
            let destino = ditado.escrevendoEm.map {
                ditado.aoVivo ? String(localized: "Escrevendo no \($0)  ·  ") : String(localized: "Entra no \($0) ao parar  ·  ")
            }
            Text("\(destino ?? "")\(Acao.ditar.atalho.descricao) para parar  ·  esc para cancelar")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

/// Barras que acompanham o volume da voz, como no ditado do sistema.
struct Onda: View {
    let niveis: [Float]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(niveis.indices, id: \.self) { i in
                Capsule()
                    .frame(width: 3, height: 3 + CGFloat(niveis[i]) * 26)
                    .opacity(0.35 + Double(niveis[i]) * 0.65)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 30)
        .foregroundStyle(.tint)
        .animation(.linear(duration: 0.08), value: niveis)
    }
}
