import Foundation

/// Estado da transcrição do Mac na ilha do Kizami, o app irmão que desenha uma ilha em volta do notch.
/// Vai por notificação distribuída, o protocolo do próprio Kizami: sem dependência, e com o Kizami fechado
/// ninguém escuta e nada acontece. Qualquer processo do Mac pode ler essas notificações, então só passa estado
/// e contagem, nunca o que foi transcrito.
enum Ilha {
    private struct Atividade: Encodable {
        let id: String
        let titulo: String
        let detalhe: String?
        let simbolo: String
        let cor: String
        let expira: Double
        let prioridade: String
    }

    private static let id = "kanji-transcricao"
    private static let prefixo = "io.github.henriquebap.kizami."

    /// Reenviar com o mesmo id troca a atividade, mas a ilha desce de novo para avisar: só nas mudanças de estado.
    /// - cor: uma das cores do Kizami (vermelho, laranja, amarelo, verde, azul, roxo, rosa, cinza).
    /// - expira: segundos na ilha; 0 fica até `remover`.
    /// - prioridade: baixa, normal, alta ou urgente. A ilha ordena por ela, e "baixa" entra sem descer.
    ///   Um Kizami anterior ao campo ignora e trata como normal.
    static func mostrar(_ titulo: String, detalhe: String? = nil, simbolo: String, cor: String, expira: Double = 0,
                        prioridade: String) {
        let atividade = Atividade(id: id, titulo: titulo, detalhe: detalhe, simbolo: simbolo, cor: cor, expira: expira,
                                  prioridade: prioridade)
        guard let json = try? JSONEncoder().encode(atividade) else { return }
        postar("enviar", String(decoding: json, as: UTF8.self))
    }

    static func remover() {
        postar("remover", id)
    }

    /// `deliverImmediately`: o Kizami nunca é o app ativo, e sem isso o macOS pode segurar o aviso.
    private static func postar(_ acao: String, _ objeto: String) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(prefixo + acao), object: objeto, userInfo: nil, deliverImmediately: true)
    }
}
