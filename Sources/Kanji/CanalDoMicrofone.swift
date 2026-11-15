import AVFoundation
import CoreAudio

/// O microfone na sessão do Mac. Liga sozinho quando outro app (Zoom, Meet, Teams) abre o microfone, que é o sinal
/// de uma chamada; num vídeo ninguém usa o microfone e a voz da sala só atrapalharia. O que ele ouve vira "Você".
/// Com cancelamento de eco: sem fone, a caixa de som tocando a chamada entraria como se fosse você falando.
@MainActor
final class CanalDoMicrofone {
    private let captura = CapturaAoVivo()
    private var vigia: Timer?
    private var relogio = Date()  // começo da sessão: o tempo dos trechos é contado a partir daqui
    private var deslocamento: Double?  // quando o microfone ligou, em segundos da sessão; nil = desligado
    private var ocupado = false  // ligando ou desligando
    private var semChamadaDesde: Date?
    private var aoTrecho: (String, [Palavra]) -> Void = { _, _ in }

    /// - aoTrecho: texto final (fusão PT+EN e glossário) e palavras já no tempo da sessão.
    func vigiar(desde relogio: Date, aoTrecho: @escaping (String, [Palavra]) -> Void) {
        (self.relogio, self.aoTrecho, semChamadaDesde) = (relogio, aoTrecho, nil)
        vigia = .scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { self.verificar() }
        }
        verificar()
    }

    func parar() async {
        vigia?.invalidate()
        vigia = nil
        await desligar()
    }

    private func verificar() {
        guard !ocupado else { return }
        let chamada = Self.appNoMicrofone()
        if let chamada, deslocamento == nil {
            Task { await ligar(por: chamada) }
        } else if chamada == nil, deslocamento != nil {
            // Uma chamada pode soltar o microfone por instantes (trocar de dispositivo, mudo em alguns apps).
            let desde = semChamadaDesde ?? .now
            semChamadaDesde = desde
            if Date.now.timeIntervalSince(desde) > 10 { Task { await desligar() } }
        } else {
            semChamadaDesde = nil
        }
    }

    private func ligar(por app: String) async {
        ocupado = true
        defer { ocupado = false }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            return registro.notice("chamada no \(app, privacy: .public), mas sem acesso ao microfone; segue só o áudio do Mac")
        }
        let inicio = Date.now.timeIntervalSince(relogio)
        do {
            let idioma = UserDefaults.standard.string(forKey: Ajustes.idioma) ?? "pt_BR"
            try await captura.iniciar(
                idioma: idioma,
                ingles: UserDefaults.standard.bool(forKey: Ajustes.misturarIngles) && idioma.hasPrefix("pt"),
                semEco: true,
                aoNivel: { _ in },
                aoTexto: { _, _ in },
                aoTrecho: { [weak self] texto, palavras in self?.entregar(texto, palavras, desde: inicio) })
            deslocamento = inicio
            registro.notice("microfone ligado: \(app, privacy: .public) está usando o microfone")
        } catch {
            await captura.cancelar()
            registro.error("microfone não ligou: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func desligar() async {
        guard deslocamento != nil else { return }
        ocupado = true
        defer { ocupado = false }
        _ = try? await captura.parar()  // os últimos trechos chegam por `entregar` durante a finalização
        deslocamento = nil
        semChamadaDesde = nil
        registro.notice("microfone desligado: nenhuma chamada usando o microfone")
    }

    private func entregar(_ texto: String, _ palavras: [Palavra], desde inicio: Double) {
        Task {
            let final = await captura.textoFinal(texto, palavras, glossario: Ditado.glossario)
            aoTrecho(final, palavras.map {
                Palavra(texto: $0.texto, inicio: $0.inicio + inicio, fim: $0.fim + inicio, confianca: $0.confianca)
            })
        }
    }

    /// Serviços do macOS que abrem o microfone sem ser chamada: o CoreSpeech (Siri, Ditado) abriu por 8 s no meio de
    /// um teste e ligou o canal à toa.
    nonisolated static let naoSaoChamada = ["com.apple.CoreSpeech", "com.apple.corespeechd", "com.apple.siri",
                                            "com.apple.assistant", "com.apple.SpeechRecognitionCore"]

    /// Bundle ID de outro app com o microfone aberto, ou nil. Outra cópia do Kanji (um ditado) não conta.
    nonisolated static func appNoMicrofone() -> String? {
        let eu = getpid()
        let processos = (try? AudioHardwareSystem.shared.processes) ?? []
        return processos.lazy.compactMap { processo -> String? in
            guard (try? processo.isRunningInput) == true, (try? processo.pid) != eu else { return nil }
            let app = (try? processo.bundleID) ?? nil
            if app == Bundle.main.bundleIdentifier || naoSaoChamada.contains(where: { app?.hasPrefix($0) == true }) { return nil }
            return app ?? "?"
        }.first
    }
}
