// Confere a tradução da interface: toda string visível no código precisa de entrada em en.lproj.
// As chaves são o próprio texto em português; pt-BR.lproj existe só para o macOS reconhecer o idioma.
// Uso: swift scripts/check-localization.swift   (com build/Kanji.app, também lê o bundle compilado)
import Foundation

let raiz = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let fontes = raiz.appending(path: "Sources/Kanji")
let tabelas = ["en.lproj/Localizable.strings", "pt-BR.lproj/Localizable.strings", "en.lproj/InfoPlist.strings"]
var falhas = 0

func falhar(_ mensagem: String) {
    print("FALHA: \(mensagem)")
    falhas += 1
}

// Inicializadores do SwiftUI que recebem LocalizedStringKey, e rótulos de argumento que levam texto da interface.
let inicio = try! NSRegularExpression(pattern:
    #"(?:\b(?:Text|Button|Toggle|Section|Picker|Tab|LabeledContent|GroupBox|TextField|SecureField|Label|CommandMenu|ContentUnavailableView)\(\s*|\b(?:localized|titulo|detalhe|texto|ajuda|prompt|withTitle):\s*)""#)

/// Lê o literal que começa logo depois das aspas e devolve a chave como o Foundation a monta:
/// cada interpolação vira %@ e os escapes viram o caractere.
/// ponytail: supõe interpolação de String ou Text (%@); um Int no texto viraria %lld e precisaria de ajuste aqui.
func chave(_ s: [Character], _ comeco: Int) -> String {
    var i = comeco, saida = ""
    while i < s.count, s[i] != "\"" {
        if s[i] == "\\", i + 1 < s.count {
            let c = s[i + 1]
            if c == "(" {  // pula a interpolação inteira, inclusive literais aninhados
                var nivel = 1, dentroDeLiteral = false
                i += 2
                while i < s.count, nivel > 0 {
                    if s[i] == "\\" { i += 2; continue }
                    if s[i] == "\"" { dentroDeLiteral.toggle() }
                    if !dentroDeLiteral { nivel += s[i] == "(" ? 1 : s[i] == ")" ? -1 : 0 }
                    i += 1
                }
                saida += "%@"
                continue
            }
            saida.append(c == "n" ? "\n" : c == "t" ? "\t" : c)
            i += 2
            continue
        }
        saida.append(s[i])
        i += 1
    }
    return saida
}

func especificadores(_ texto: String) -> Int {
    texto.components(separatedBy: "%@").count - 1
}

// 1. Chaves usadas no código.
var usadas: [String: String] = [:]  // chave → arquivo
let arquivos = try FileManager.default.contentsOfDirectory(at: fontes, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
for arquivo in arquivos {
    let texto = try String(contentsOf: arquivo, encoding: .utf8)
    let caracteres = Array(texto)
    let ns = texto as NSString
    for achado in inicio.matches(in: texto, range: NSRange(location: 0, length: ns.length)) {
        let prefixo = ns.substring(to: achado.range.location + achado.range.length)
        let k = chave(caracteres, prefixo.count)
        // "%@ %@", "· %@": sem palavra, nada a traduzir.
        guard k.replacingOccurrences(of: "%@", with: "").contains(where: \.isLetter) else { continue }
        usadas[k] = arquivo.lastPathComponent
    }
}

// 2. Os arquivos .strings são válidos.
for tabela in tabelas {
    let processo = Process()
    processo.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
    processo.arguments = ["-lint", "-s", raiz.appending(path: "Resources/\(tabela)").path]
    try processo.run()
    processo.waitUntilExit()
    if processo.terminationStatus != 0 { falhar("plutil -lint recusou Resources/\(tabela)") }
}

// 3. Toda chave tem tradução em inglês, com os mesmos %@, e não sobra tradução sem uso.
let ingles = NSDictionary(contentsOf: raiz.appending(path: "Resources/en.lproj/Localizable.strings")) as? [String: String] ?? [:]
for (k, arquivo) in usadas.sorted(by: { $0.key < $1.key }) {
    guard let traducao = ingles[k] else { falhar("sem inglês (\(arquivo)): \(k.debugDescription)"); continue }
    if especificadores(traducao) != especificadores(k) { falhar("número de %@ diferente: \(k.debugDescription)") }
}
for k in ingles.keys.sorted() where usadas[k] == nil { falhar("tradução sem uso no código: \(k.debugDescription)") }
print("\(usadas.count) textos da interface, \(ingles.count) traduções em inglês")

// 4. Com o app compilado: o macOS escolhe o idioma certo e acha as traduções no bundle.
let app = raiz.appending(path: "build/Kanji.app")
if let bundle = Bundle(url: app) {
    print("região de desenvolvimento: \(bundle.developmentLocalization ?? "nenhuma"), idiomas: \(Set(bundle.localizations).sorted())")
    for preferido in ["en", "en-GB", "pt-BR", "pt-PT", "fr"] {
        let escolhido = Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: [preferido]).first ?? "?"
        print("Mac em \(preferido) → interface em \(escolhido)")
    }
    for idioma in ["en", "pt-BR"] {
        guard let caminho = bundle.path(forResource: idioma, ofType: "lproj"), let lproj = Bundle(path: caminho) else {
            falhar("\(idioma).lproj não está no bundle")
            continue
        }
        // Sem tradução, o macOS usa a própria chave: é o caso de todo o pt-BR.
        for k in ["Ajustes…", "Começar a ditar  (%@)"] {
            print("  [\(idioma)] \(k) → \(lproj.localizedString(forKey: k, value: nil, table: nil))")
        }
        // A mesma interpolação do Painel: confirma que a chave montada com %@ é a que o Foundation procura.
        print("  [\(idioma)] String(localized:) → \(String(localized: "Revisando com \("o Claude")…", bundle: lproj))")
    }
    if bundle.developmentLocalization != "pt-BR" { falhar("CFBundleDevelopmentRegion do bundle não é pt-BR") }
} else {
    print("build/Kanji.app não encontrado: rode make app para conferir também o bundle")
}

if falhas > 0 {
    print("\(falhas) falha(s)")
    exit(1)
}
print("ok")
