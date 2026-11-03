import AppKit
import ApplicationServices

@MainActor
enum Area {
    /// Cola o texto no app em foco simulando ⌘V. O ditado fica no clipboard: antes o clipboard anterior voltava
    /// 400 ms depois e, quando o ⌘V caía num lugar sem campo, o texto sumia. Retorna se colou.
    static func colar(_ texto: String, sozinho: Bool, historico: Historico) -> Bool {
        copiar(texto, historico: historico)
        guard sozinho, temAcessibilidade(pedir: !jaPediu) else { return false }
        let fonte = CGEventSource(stateID: .combinedSessionState)
        for desce in [true, false] {
            let evento = CGEvent(keyboardEventSource: fonte, virtualKey: 9, keyDown: desce)  // 9 = V
            evento?.flags = .maskCommand
            evento?.post(tap: .cghidEventTap)
        }
        return true
    }

    static func copiar(_ texto: String, historico: Historico) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
        historico.ignorarMudancaAtual()
    }

    private static var jaPediu = false  // o aviso do sistema aparece uma vez por execução, não a cada ditado

    static func temAcessibilidade(pedir: Bool = false) -> Bool {
        if pedir { jaPediu = true }
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": pedir] as CFDictionary)
    }
}

/// Feedback sonoro de cada etapa, com sons do sistema (nada para empacotar).
enum Som: String {
    case inicio = "Tink", fim = "Pop", pronto = "Glass", vazio = "Funk", erro = "Basso"

    @MainActor static func tocar(_ som: Som) {
        guard UserDefaults.standard.bool(forKey: Ajustes.sons) else { return }
        NSSound(named: som.rawValue)?.play()
    }
}
