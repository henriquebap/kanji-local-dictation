import Foundation

/// A resposta da nuvem chegando aos poucos (server-sent events). No modo entrevista, o primeiro tópico aparece
/// enquanto o resto ainda está sendo escrito, em vez de esperar os ~3 s da resposta inteira (medido).
enum Streaming {
    /// O que uma linha "data: {…}" traz, no formato da Anthropic (Messages) ou no da OpenAI (Chat Completions).
    struct Evento: Equatable {
        var texto = ""
        var fim: String?
        var erro: String?
        var cacheLido: Int?
        var cacheGravado: Int?
    }

    /// nil para o que não importa: linhas "event:", "ping", o "[DONE]" da OpenAI, JSON quebrado.
    static func evento(_ linha: String, claude: Bool) -> Evento? {
        guard linha.hasPrefix("data:"),
              let json = (try? JSONSerialization.jsonObject(with: Data(linha.dropFirst(5).utf8))) as? [String: Any]
        else { return nil }
        var e = Evento()
        if let erro = json["error"] as? [String: Any] {
            e.erro = erro["message"] as? String ?? "erro no streaming"
            return e
        }
        guard claude else {
            let escolha = (json["choices"] as? [[String: Any]])?.first
            e.texto = (escolha?["delta"] as? [String: Any])?["content"] as? String ?? ""
            e.fim = escolha?["finish_reason"] as? String
            return e
        }
        switch json["type"] as? String {
        case "content_block_delta":
            e.texto = (json["delta"] as? [String: Any])?["text"] as? String ?? ""
        case "message_delta":
            e.fim = (json["delta"] as? [String: Any])?["stop_reason"] as? String
        case "message_start":
            let uso = (json["message"] as? [String: Any])?["usage"] as? [String: Any]
            (e.cacheLido, e.cacheGravado) = (uso?["cache_read_input_tokens"] as? Int, uso?["cache_creation_input_tokens"] as? Int)
        default:
            return nil
        }
        return e
    }
}
