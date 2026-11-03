import AppKit
import ApplicationServices

/// Campo de texto em foco em outro app. O ditado é escrito nele ao vivo pela API de Acessibilidade,
/// sem ⌘V. No fim, o trecho escrito é trocado pela versão ajustada.
@MainActor
final class Alvo {
    let app: String?
    private let elemento: AXUIElement
    private let inicio: Int        // posição do cursor quando a gravação começou (UTF-16)
    private(set) var escrito = ""  // tudo que este ditado já pôs no campo

    private init(elemento: AXUIElement, inicio: Int, app: String?) {
        self.elemento = elemento
        self.inicio = inicio
        self.app = app
    }

    /// nil quando não há campo editável em foco (ou sem permissão): aí o texto vai para o painel.
    static func emFoco() -> Alvo? {
        guard Area.temAcessibilidade() else {
            registro.notice("sem campo: Kanji não tem permissão de Acessibilidade")
            return nil
        }
        guard let frente = NSWorkspace.shared.frontmostApplication else { return nil }
        let app = AXUIElementCreateApplication(frente.processIdentifier)
        // Chrome e apps Electron só montam a árvore de acessibilidade quando um leitor pede; sem isso o foco
        // vinha vazio (-25212) e o texto só entrava colado no fim. Nos outros apps o atributo é ignorado.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var foco: CFTypeRef?
        let resultado = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &foco)
        guard resultado == .success, let foco, CFGetTypeID(foco) == AXUIElementGetTypeID() else {
            registro.notice("sem campo: foco não encontrado (\(resultado.rawValue))")
            return nil
        }
        let elemento = foco as! AXUIElement  // tipo conferido acima
        var editavel: DarwinBoolean = false
        let podeEscrever = AXUIElementIsAttributeSettable(elemento, kAXSelectedTextAttribute as CFString, &editavel)
        guard podeEscrever == .success, editavel.boolValue, let faixa = faixaSelecionada(elemento) else {
            registro.notice("sem campo: \(papel(elemento), privacy: .public) não aceita texto (\(podeEscrever.rawValue), \(editavel.boolValue))")
            return nil
        }
        registro.notice("campo: \(papel(elemento), privacy: .public) em \(frente.localizedName ?? "?", privacy: .public)")
        return Alvo(elemento: elemento, inicio: faixa.location, app: frente.localizedName)
    }

    /// Deixa no campo exatamente `texto` como "o que este ditado escreveu", mexendo só na parte que mudou:
    /// o rascunho do reconhecedor muda a cada instante e só o final dele é reescrito, sem piscar o resto.
    /// Recusa (false) se o trecho já escrito não estiver mais intacto: a pessoa clicou em outro lugar ou editou.
    func atualizar(para texto: String) -> Bool {
        guard texto != escrito else { return true }
        if !escrito.isEmpty {
            guard conteudo(em: CFRange(location: inicio, length: escrito.utf16.count)) == escrito else { return false }
        }
        let comum = String(zip(escrito, texto).prefix { $0 == $1 }.map(\.0)).utf16.count
        var faixa = CFRange(location: inicio + comum, length: escrito.utf16.count - comum)
        let novo = String(decoding: Array(texto.utf16)[comum...], as: UTF16.self)
        guard let valor = AXValueCreate(.cfRange, &faixa) else { return false }
        let selecao = AXUIElementSetAttributeValue(elemento, kAXSelectedTextRangeAttribute as CFString, valor)
        let escrita = AXUIElementSetAttributeValue(elemento, kAXSelectedTextAttribute as CFString, novo as CFString)
        guard selecao == .success, escrita == .success else {
            registro.notice("campo recusou a escrita (seleção \(selecao.rawValue), texto \(escrita.rawValue))")
            return false
        }
        escrito = texto
        return true
    }

    private func conteudo(em faixa: CFRange) -> String? {
        var r = faixa
        var saida: CFTypeRef?
        if let parametro = AXValueCreate(.cfRange, &r),
           AXUIElementCopyParameterizedAttributeValue(elemento, kAXStringForRangeParameterizedAttribute as CFString,
                                                      parametro, &saida) == .success {
            return saida as? String
        }
        // Alguns apps não respondem ao atributo de trecho: lê o valor inteiro e recorta.
        guard AXUIElementCopyAttributeValue(elemento, kAXValueAttribute as CFString, &saida) == .success,
              let tudo = saida as? String, faixa.location + faixa.length <= tudo.utf16.count
        else { return nil }
        let utf16 = Array(tudo.utf16)[faixa.location..<(faixa.location + faixa.length)]
        return String(decoding: utf16, as: UTF16.self)
    }

    private static func papel(_ elemento: AXUIElement) -> String {
        var valor: CFTypeRef?
        AXUIElementCopyAttributeValue(elemento, kAXRoleAttribute as CFString, &valor)
        return valor as? String ?? "?"
    }

    private static func faixaSelecionada(_ elemento: AXUIElement) -> CFRange? {
        var valor: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elemento, kAXSelectedTextRangeAttribute as CFString, &valor) == .success,
              let valor, CFGetTypeID(valor) == AXValueGetTypeID()
        else { return nil }
        var faixa = CFRange()
        return AXValueGetValue(valor as! AXValue, .cfRange, &faixa) ? faixa : nil  // tipo conferido acima
    }
}
