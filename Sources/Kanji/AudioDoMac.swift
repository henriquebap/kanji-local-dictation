import AVFoundation
import CoreAudio

/// O que os apps do Mac estão tocando, por um process tap do Core Audio. Pede só a permissão
/// "Gravação de Áudio do Sistema" (a de Gravação de Tela, do ScreenCaptureKit, é bem mais ampla) e pega o som
/// antes do dispositivo de saída: tanto faz fone ou caixa de som. Sem `NSAudioCaptureUsageDescription` no
/// Info.plist o tap grava silêncio, sem erro nenhum.
@MainActor
final class AudioDoMac {
    enum Falha: LocalizedError {
        case semTap, semSaida, semFormato, semDispositivo, semIO(OSStatus)

        var errorDescription: String? {
            switch self {
            case .semTap: String(localized: "O macOS não criou a captura do áudio do Mac.")
            case .semSaida: String(localized: "Nenhuma saída de som ativa no Mac.")
            case .semFormato: String(localized: "Formato de áudio do Mac não reconhecido.")
            case .semDispositivo: String(localized: "O macOS não criou o dispositivo de captura.")
            case .semIO(let status): String(localized: "O áudio do Mac não começou (erro \(String(status))).")
            }
        }
    }

    private let sistema = AudioHardwareSystem.shared
    private var tap: AudioHardwareTap?
    private var dispositivo: AudioHardwareAggregateDevice?
    private var proc: AudioDeviceIOProcID?

    /// - aoBuffer: chamado na thread de áudio do Core Audio, com o som já misturado em mono.
    func iniciar(aoBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        let descricao = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        // Fora pelo bundle ID, e não pelo processo: o Kanji só vira processo do Core Audio depois de tocar o
        // primeiro som, e sem isso os sons de status entrariam na transcrição.
        descricao.bundleIDs = [Bundle.main.bundleIdentifier ?? "io.github.henriquebap.kanji"]
        descricao.isPrivate = true
        descricao.name = "Kanji"
        do {
            guard let tap = try sistema.makeProcessTap(description: descricao) else { throw Falha.semTap }
            self.tap = tap
            var asbd = try tap.format
            guard let formato = AVAudioFormat(streamDescription: &asbd) else { throw Falha.semFormato }
            // ponytail: o relógio é a saída padrão na hora de começar; trocar de fone no meio pode calar a captura.
            // Ouvir kAudioHardwarePropertyDefaultOutputDevice e recriar o dispositivo se isso aparecer no uso.
            guard let saida = try sistema.defaultOutputDevice?.uid else { throw Falha.semSaida }
            let configuracao: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Kanji",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: saida,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: saida]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: try tap.uid]],
            ]
            guard let dispositivo = try sistema.makeAggregateDevice(description: configuracao) else { throw Falha.semDispositivo }
            self.dispositivo = dispositivo
            var proc: AudioDeviceIOProcID?
            let status = AudioDeviceCreateIOProcIDWithBlock(&proc, dispositivo.id, DispatchQueue(label: "kanji.audio-do-mac"),
                                                            Self.bloco(formato: formato, aoBuffer: aoBuffer))
            guard status == noErr, let proc else { throw Falha.semIO(status) }
            self.proc = proc
            try dispositivo.start(IOProcID: proc)
            registro.notice("áudio do Mac: \(Int(asbd.mSampleRate), privacy: .public) Hz, \(asbd.mChannelsPerFrame, privacy: .public) canal")
        } catch {
            parar()
            throw error
        }
    }

    func parar() {
        if let dispositivo, let proc {
            try? dispositivo.stop(IOProcID: proc)
            AudioDeviceDestroyIOProcID(dispositivo.id, proc)
        }
        if let dispositivo { try? sistema.destroyAggregateDevice(dispositivo) }
        if let tap { try? sistema.destroyProcessTap(tap) }
        (proc, dispositivo, tap) = (nil, nil, nil)
    }

    /// Fica `nonisolated` pelo mesmo motivo do tap do microfone: o bloco roda na thread de áudio e não pode
    /// herdar o MainActor.
    nonisolated private static func bloco(formato: AVAudioFormat,
                                          aoBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) -> AudioDeviceIOBlock {
        return { _, entrada, _, _, _ in
            // Sem cópia: o buffer só vale dentro deste bloco, e o conversor do SpeechAnalyzer copia ao converter.
            guard let buffer = AVAudioPCMBuffer(pcmFormat: formato, bufferListNoCopy: entrada, deallocator: nil) else { return }
            aoBuffer(buffer)
        }
    }
}
