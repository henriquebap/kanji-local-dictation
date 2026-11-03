import AVFoundation
import SwiftUI

/// Abre sozinha na primeira vez (e pelo menu): o que o macOS precisa liberar, com o estado de cada item.
struct PrimeirosPassosView: View {
    let aoTerminar: () -> Void

    var body: some View {
        // As permissões mudam fora do app (Ajustes do Sistema): reler a cada segundo é o jeito simples de acompanhar.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 16) {
                Text("Bem-vindo ao Kanji").font(.largeTitle.bold())
                Text("Ditado em português e inglês, escrito onde está o cursor. Três liberações (e uma opcional) e pronto.")
                    .foregroundStyle(.secondary)
                Passo(numero: 1, titulo: "Microfone",
                      detalhe: "Para ouvir só enquanto o atalho está ativo. O áudio é transcrito no próprio Mac.",
                      feito: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized) {
                    Button("Permitir") { Task { await pedirMicrofone() } }
                }
                Passo(numero: 2, titulo: "Acessibilidade",
                      detalhe: "Para escrever no app em que você está. Ative o Kanji na lista que vai abrir.",
                      feito: Area.temAcessibilidade()) {
                    Button("Abrir Ajustes do Sistema") {
                        _ = Area.temAcessibilidade(pedir: true)  // põe o Kanji na lista
                        abrir("Privacy_Accessibility")
                    }
                }
                Passo(numero: 3, titulo: "Apple Intelligence",
                      detalhe: "Revisão grátis e sem internet. Ative em Ajustes do Sistema › Apple Intelligence e Siri.",
                      feito: Correcao.disponivel) { EmptyView() }
                Passo(numero: 4, titulo: "Opcional: revisão na nuvem",
                      detalhe: "Com uma chave sua (Claude, OpenAI, Gemini…), o texto inteiro é revisado ao parar: listas, nomes, jargão.",
                      feito: Nuvem.pronto != nil) {
                    Button("Escolher") { Kanji.shared.janelas.mostrarAjustes() }
                }
                Text("O Kanji também guarda o que você copia, para achar depois no histórico. Senhas marcadas pelos gerenciadores e textos com cara de chave ficam de fora; dá para desligar em Ajustes › Histórico.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Divider()
                Text("Para ditar: clique num campo de texto em qualquer app, aperte **\(Acao.ditar.atalho.descricao)** e fale. Aperte de novo para parar; **esc** cancela.")
                HStack {
                    Spacer()
                    Button("Começar a usar", action: aoTerminar)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(28)
            .frame(width: 560)
        }
    }

    private func pedirMicrofone() async {
        // Negado antes, o macOS não pergunta de novo: só pelos Ajustes do Sistema.
        if !(await AVCaptureDevice.requestAccess(for: .audio)) { abrir("Privacy_Microphone") }
    }

    private func abrir(_ painel: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(painel)")!)
    }
}

private struct Passo<Acao: View>: View {
    let numero: Int
    let titulo: String
    let detalhe: String
    let feito: Bool
    @ViewBuilder let acao: () -> Acao

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: feito ? "checkmark.circle.fill" : "\(numero).circle")
                .font(.title2)
                .foregroundStyle(feito ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.headline)
                Text(detalhe).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !feito { acao() }
        }
    }
}
