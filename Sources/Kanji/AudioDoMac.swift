import AVFoundation
import CoreAudio
import os

/// O que os apps do Mac estão tocando, por um process tap do Core Audio. Pede só a permissão
/// "Gravação de Áudio do Sistema" (a de Gravação de Tela, do ScreenCaptureKit, é bem mais ampla) e pega o som
/// antes do dispositivo de saída: tanto faz fone ou caixa de som. Sem `NSAudioCaptureUsageDescription` no
/// Info.plist o tap grava silêncio, sem erro nenhum.
@MainActor
final class AudioDoMac {
    enum Falha: LocalizedError {
        case semTap, semFormato, semDispositivo, semIO(OSStatus)

        var errorDescription: String? {
            switch self {
            case .semTap: String(localized: "O macOS não criou a captura do áudio do Mac.")
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
    // A saída pode mudar de taxa no meio da sessão: o AirPods cai de 48 para 24 kHz quando uma chamada abre o
    // microfone (medido). O dispositivo agregado, que segue o AirPods, passa a entregar 24 kHz enquanto o tap
    // continua dizendo 48 kHz; lido como 48 kHz, o reconhecedor não entendia nada. O bloco de áudio lê daqui o
    // formato atual a cada chamada, e o aviso de mudança de taxa do agregado o atualiza.
    private let formato = OSAllocatedUnfairLock<AVAudioFormat?>(initialState: nil)
    private var ouvinte: AudioObjectPropertyListenerBlock?
    private let fila = DispatchQueue(label: "kanji.audio-do-mac")
    private static var enderecoDaTaxa: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

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
            guard let inicial = AVAudioFormat(streamDescription: &asbd) else { throw Falha.semFormato }
            formato.withLock { $0 = inicial }
            // Só o tap, sem a saída como dispositivo: com o AirPods como relógio do agregado, a captura parava inteira
            // enquanto ele ficava no modo de chamada (o relógio do reconhecedor andou 38 s a menos numa chamada de 38 s).
            let configuracao: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Kanji",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: try tap.uid]],
            ]
            guard let dispositivo = try sistema.makeAggregateDevice(description: configuracao) else { throw Falha.semDispositivo }
            self.dispositivo = dispositivo
            let ouvinte = Self.ouvinte(dispositivo: dispositivo, base: asbd, formato: formato)
            var endereco = Self.enderecoDaTaxa
            AudioObjectAddPropertyListenerBlock(dispositivo.id, &endereco, fila, ouvinte)
            self.ouvinte = ouvinte
            ouvinte(1, &endereco)  // o agregado pode já nascer numa taxa diferente da do tap
            var proc: AudioDeviceIOProcID?
            let status = AudioDeviceCreateIOProcIDWithBlock(&proc, dispositivo.id, fila,
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
        if let dispositivo, let ouvinte {
            var endereco = Self.enderecoDaTaxa
            AudioObjectRemovePropertyListenerBlock(dispositivo.id, &endereco, fila, ouvinte)
        }
        if let dispositivo { try? sistema.destroyAggregateDevice(dispositivo) }
        if let tap { try? sistema.destroyProcessTap(tap) }
        (proc, dispositivo, tap, ouvinte) = (nil, nil, nil, nil)
    }

    /// Fica `nonisolated` pelo mesmo motivo do tap do microfone: o bloco roda na thread de áudio e não pode
    /// herdar o MainActor.
    nonisolated private static func bloco(formato: OSAllocatedUnfairLock<AVAudioFormat?>,
                                          aoBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) -> AudioDeviceIOBlock {
        return { _, entrada, _, _, _ in
            // Sem cópia: o buffer só vale dentro deste bloco, e o conversor do SpeechAnalyzer copia ao converter.
            guard let atual = formato.withLock({ $0 }),
                  let buffer = AVAudioPCMBuffer(pcmFormat: atual, bufferListNoCopy: entrada, deallocator: nil) else { return }
            aoBuffer(buffer)
        }
    }

    /// Fora do ator pelo mesmo motivo: o aviso de mudança chega na fila do áudio.
    nonisolated private static func ouvinte(dispositivo: AudioHardwareAggregateDevice, base: AudioStreamBasicDescription,
                                            formato: OSAllocatedUnfairLock<AVAudioFormat?>) -> AudioObjectPropertyListenerBlock {
        return { _, _ in
            guard let taxa = try? dispositivo.nominalSampleRate, taxa > 0 else { return }
            var asbd = base
            asbd.mSampleRate = taxa
            guard let novo = AVAudioFormat(streamDescription: &asbd) else { return }
            let anterior = formato.withLock { atual in
                defer { atual = novo }
                return atual?.sampleRate
            }
            if anterior != taxa { registro.notice("áudio do Mac a \(Int(taxa), privacy: .public) Hz") }
        }
    }
}
