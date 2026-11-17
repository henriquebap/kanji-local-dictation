import AppKit
import Observation

/// As transcrições salvas na pasta, para a janela do Kanji: ler, renomear quem fala, resumir e apagar.
/// Os arquivos continuam sendo a fonte: o que muda aqui é regravado lá, e o Finder vê o mesmo.
@MainActor @Observable
final class Transcricoes {
    static let shared = Transcricoes()
    private static var pasta: URL { SessaoDoMac.pasta }

    private(set) var itens: [Transcricao] = []
    private(set) var resumos: [Transcricao.ID: [Analise: String]] = [:]
    /// Uma chamada à nuvem por transcrição de cada vez; o valor diz qual, para a mensagem de espera.
    private(set) var resumindo: [Transcricao.ID: Analise] = [:]
    private(set) var erros: [Transcricao.ID: String] = [:]
    /// Onde o feedback foi salvo na pasta de notas ("entrevistas/…md"), para a tela confirmar.
    private(set) var salvas: [Transcricao.ID: String] = [:]
    /// A sessão cujo feedback espera confirmação para ir às notas.
    var confirmarNotas: Transcricao.ID?
    /// De onde cada uma foi lida, sem a extensão: a pessoa pode ter renomeado o arquivo no Finder.
    @ObservationIgnored private var bases: [Transcricao.ID: URL] = [:]
    /// O Markdown de cada uma, montado uma vez para a busca não refazer tudo a cada tecla.
    private(set) var textos: [Transcricao.ID: String] = [:]

    /// ponytail: lê todos os JSON de uma vez, na thread principal; dezenas de sessões levam milissegundos.
    /// Ler em segundo plano, ou só o começo de cada arquivo, se a pasta passar de centenas.
    func carregar() {
        let urls = ((try? FileManager.default.contentsOfDirectory(at: Self.pasta, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            // Uma cópia do Finder ("… copy") repete o id: fica a original, que tem o nome mais curto. Só em ordem
            // alfabética a cópia vinha antes (o espaço vem antes do ponto).
            .sorted { ($0.lastPathComponent.count, $0.lastPathComponent) < ($1.lastPathComponent.count, $1.lastPathComponent) }
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
            guard let base = bases[t.id] else { return }
            resumos[t.id] = Analise.allCases.reduce(into: [:]) { lidos, a in
                lidos[a] = try? String(contentsOf: Transcricao.resumo(de: base, a), encoding: .utf8)
            }
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
        guard !emAndamento(t), resumindo[t.id] == nil, let base = bases[t.id] else { return }
        let arquivos = [base.appendingPathExtension("json"), base.appendingPathExtension("md")]
            + Analise.allCases.map { Transcricao.resumo(de: base, $0) }
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

    /// Só o texto vai para o provedor da nuvem escolhido; o resultado fica num `… resumo.md` (ou `… entrevista.md`) ao lado.
    func resumir(_ t: Transcricao, _ analise: Analise = .resumo) async {
        guard resumindo[t.id] == nil else { return }
        resumindo[t.id] = analise
        erros[t.id] = nil
        defer { resumindo[t.id] = nil }
        do {
            let texto = try await Nuvem.resumir(t.markdown(), idioma: t.idiomaPrincipal, analise: analise)
            // A pessoa pode ter recarregado a lista durante os até 2 min de espera.
            guard let base = bases[t.id] else { return }
            let conteudo = "# \(t.data)\n\n\(texto)\n"  // sem "Resumo": a palavra seria em português num resumo em inglês
            try Data(conteudo.utf8).write(to: Transcricao.resumo(de: base, analise), options: .atomic)
            resumos[t.id, default: [:]][analise] = conteudo
        } catch {
            registro.error("resumo falhou: \(error.localizedDescription, privacy: .private)")  // pode citar a transcrição
            erros[t.id] = error.localizedDescription
        }
    }

    /// O feedback da entrevista vai para `entrevistas/` na pasta de notas, e o modo entrevista passa a saber o que
    /// faltou nas respostas. Só depois da confirmação (a pasta é da pessoa); salvar de novo substitui o arquivo.
    func salvarNasNotas(_ t: Transcricao) {
        guard let caminho = UserDefaults.standard.string(forKey: Ajustes.pastaDasNotas), let base = bases[t.id],
              let feedback = resumos[t.id]?[.entrevista] else { return }
        let raiz = URL(filePath: caminho, directoryHint: .isDirectory)
        let pasta = raiz.appending(path: Notas.pastaDeEntrevistas, directoryHint: .isDirectory)
        let nome = base.lastPathComponent + ".md"
        // A pasta de notas sumiu (movida, iCloud fora do ar): criar o caminho de novo faria um vault vazio.
        guard FileManager.default.fileExists(atPath: raiz.path(percentEncoded: false)) else {
            erros[t.id] = String(localized: "Não achei a pasta de notas. Escolha de novo em Ajustes › Entrevista.")
            return
        }
        // A nota pode ter sido revisada (status verificado): salvar de novo não passa por cima.
        guard !FileManager.default.fileExists(atPath: pasta.appending(path: nome).path(percentEncoded: false)) else {
            salvas[t.id] = "\(Notas.pastaDeEntrevistas)/\(nome)"
            return
        }
        do {
            try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
            let nota = Notas.notaDeFeedback(feedback, sessao: base.lastPathComponent, hoje: .now)
            try Data(nota.utf8).write(to: pasta.appending(path: nome), options: .atomic)
            salvas[t.id] = "\(Notas.pastaDeEntrevistas)/\(nome)"
            registro.notice("feedback salvo nas notas (\(nota.count) caracteres)")
        } catch {
            registro.error("feedback não foi para as notas: \(error.localizedDescription, privacy: .private)")
            erros[t.id] = String(localized: "Não consegui salvar nas notas: \(error.localizedDescription)")
        }
    }
}
