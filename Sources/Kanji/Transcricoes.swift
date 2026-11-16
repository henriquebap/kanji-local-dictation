import AppKit
import Observation

/// As transcrições salvas na pasta, para a janela do Kanji: ler, renomear quem fala, resumir e apagar.
/// Os arquivos continuam sendo a fonte: o que muda aqui é regravado lá, e o Finder vê o mesmo.
@MainActor @Observable
final class Transcricoes {
    static let shared = Transcricoes()
    private static var pasta: URL { SessaoDoMac.pasta }

    private(set) var itens: [Transcricao] = []
    private(set) var resumos: [Transcricao.ID: String] = [:]
    private(set) var resumindo: Set<Transcricao.ID> = []
    private(set) var erros: [Transcricao.ID: String] = [:]
    /// De onde cada uma foi lida, sem a extensão: a pessoa pode ter renomeado o arquivo no Finder.
    @ObservationIgnored private var bases: [Transcricao.ID: URL] = [:]
    /// O Markdown de cada uma, montado uma vez para a busca não refazer tudo a cada tecla.
    private(set) var textos: [Transcricao.ID: String] = [:]

    /// ponytail: lê todos os JSON de uma vez, na thread principal; dezenas de sessões levam milissegundos.
    /// Ler em segundo plano, ou só o começo de cada arquivo, se a pasta passar de centenas.
    func carregar() {
        let urls = ((try? FileManager.default.contentsOfDirectory(at: Self.pasta, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }  // uma cópia do Finder ("… copy") repete o id: fica a original
        var lidas: [Transcricao] = []
        var bases: [Transcricao.ID: URL] = [:]
        for url in urls {
            do {
                let t = try Transcricao.ler(url)
                guard !t.trechos.isEmpty, bases[t.id] == nil else { continue }
                bases[t.id] = url.deletingPathExtension()
                lidas.append(t)
            } catch {
                registro.error("transcrição ilegível: \(error.localizedDescription, privacy: .private)")
            }
        }
        self.bases = bases
        itens = lidas.sorted { $0.inicio > $1.inicio }
        textos = itens.reduce(into: [:]) { $0[$1.id] = $1.markdown() }
        resumos = itens.reduce(into: [:]) { resumos, t in
            resumos[t.id] = bases[t.id].flatMap { try? String(contentsOf: Transcricao.resumo(de: $0), encoding: .utf8) }
        }
    }

    /// A sessão gravando agora reescreve o próprio arquivo a cada trecho: mexer nele daqui seria desfeito.
    /// Pelo id: a data volta do JSON sem os milissegundos e nunca bateria.
    func emAndamento(_ t: Transcricao) -> Bool {
        Kanji.shared.sessao.transcricaoAtual == t.id
    }

    /// false se o nome não serve (vazio, ou já é de outra voz) ou se não deu para salvar.
    func renomear(_ t: Transcricao, _ antigo: String, para novo: String) -> Bool {
        guard !emAndamento(t), let i = itens.firstIndex(where: { $0.id == t.id }), let base = bases[t.id] else { return false }
        var copia = itens[i]
        guard copia.renomear(antigo, para: novo) else {
            erros[t.id] = String(localized: "Esse nome está vazio ou já é de outra voz.")
            return false
        }
        do {
            try copia.gravar(base: base)
            itens[i] = copia
            textos[t.id] = copia.markdown()
            erros[t.id] = nil
            return true
        } catch {
            registro.error("falha ao renomear: \(error.localizedDescription, privacy: .private)")
            erros[t.id] = String(localized: "Não consegui salvar: \(error.localizedDescription)")
            return false
        }
    }

    /// Vai para o Lixo, não some: dá para recuperar pelo Finder.
    func apagar(_ t: Transcricao) {
        guard !emAndamento(t), !resumindo.contains(t.id), let base = bases[t.id] else { return }
        let arquivos = [base.appendingPathExtension("json"), base.appendingPathExtension("md"), Transcricao.resumo(de: base)]
        for url in arquivos where FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                registro.error("falha ao mandar para o Lixo: \(error.localizedDescription, privacy: .private)")
            }
        }
        carregar()
    }

    func mostrarNoFinder(_ t: Transcricao) {
        guard let base = bases[t.id] else { return }
        NSWorkspace.shared.activateFileViewerSelecting([base.appendingPathExtension("md")])
    }

    /// Só o texto vai para o provedor da nuvem escolhido; o resultado fica num `… resumo.md` ao lado.
    func resumir(_ t: Transcricao) async {
        guard resumindo.insert(t.id).inserted else { return }
        erros[t.id] = nil
        defer { resumindo.remove(t.id) }
        do {
            let texto = try await Nuvem.resumir(t.markdown())
            // A pessoa pode ter recarregado a lista durante os até 2 min de espera.
            guard let base = bases[t.id] else { return }
            let conteudo = "# Resumo — \(t.data)\n\n\(texto)\n"
            try Data(conteudo.utf8).write(to: Transcricao.resumo(de: base), options: .atomic)
            resumos[t.id] = conteudo
        } catch {
            registro.error("resumo falhou: \(error.localizedDescription, privacy: .private)")  // pode citar a transcrição
            erros[t.id] = error.localizedDescription
        }
    }
}
