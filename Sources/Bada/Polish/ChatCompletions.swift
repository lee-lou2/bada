import Foundation

/// Base URL, key and model for an OpenAI-compatible endpoint.
struct LLMConfig: Equatable {
    var baseURL: String
    var apiKey: String
    var model: String

    var isComplete: Bool { !baseURL.isEmpty && !apiKey.isEmpty && !model.isEmpty }
}

/// A small client for OpenAI-compatible `POST …/chat/completions`.
enum ChatCompletions {
    typealias Message = [String: String]

    enum Failure: LocalizedError {
        case invalidBaseURL
        case http(Int, String?)
        case network(URLError.Code)
        case emptyReply

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL:
                return "Base URL을 확인해 주세요"
            case let .http(code, message):
                if let message, !message.isEmpty { return "\(code) · \(message.prefix(140))" }
                switch code {
                case 401, 403: return "API 키를 확인해 주세요"
                case 404: return "주소나 모델 이름을 확인해 주세요"
                case 429: return "요청이 많아요. 잠시 뒤 다시 시도해 주세요"
                default: return "서버 응답 \(code)"
                }
            case let .network(code):
                switch code {
                case .timedOut: return "응답이 없어요 (시간 초과)"
                case .notConnectedToInternet, .networkConnectionLost: return "인터넷 연결을 확인해 주세요"
                case .cannotFindHost, .dnsLookupFailed: return "주소를 찾지 못했어요"
                case .cannotConnectToHost: return "서버에 연결할 수 없어요"
                case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate:
                    return "보안 연결 실패 · http/https를 확인해 주세요"
                case .cancelled: return "취소됐어요"
                default: return "네트워크 오류 (\(code.rawValue))"
                }
            case .emptyReply:
                return "빈 응답이 왔어요"
            }
        }
    }

    /// `…/v1` becomes `…/v1/chat/completions`; a bare host gets `/v1` first.
    /// Local hosts default to http, everything else to https.
    static func endpoint(for baseURL: String) -> URL? {
        var text = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            let host = text.split(separator: "/").first?.split(separator: ":").first.map(String.init)?.lowercased() ?? ""
            let isLocal = ["localhost", "127.0.0.1", "0.0.0.0", "[::1]"].contains(host) || host.hasSuffix(".local")
            text = (isLocal ? "http://" : "https://") + text
        }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              components.host?.isEmpty == false else { return nil }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.isEmpty {
            path = "/v1/chat/completions"
        } else if !path.hasSuffix("/chat/completions") {
            path += "/chat/completions"
        }
        components.path = path
        return components.url
    }

    /// Sends `messages` and returns the reply text.
    static func complete(_ messages: [Message], config: LLMConfig, timeout: TimeInterval) async throws -> String {
        guard let url = endpoint(for: config.baseURL) else { throw Failure.invalidBaseURL }
        let key = storageKey(url, config.model)
        var options = RequestOptions.saved(for: key) ?? RequestOptions()
        for _ in 0..<4 {
            do {
                let reply = try await send(messages, to: url, config: config, options: options, timeout: timeout)
                options.save(for: key)
                return reply
            } catch let Failure.http(code, message) where code == 400 || code == 422 {
                guard let next = options.adjusted(after: message ?? "") else { throw Failure.http(code, message) }
                Log.info("llm \(code), retrying with reasoning_effort \(next.reasoningEffort ?? "-"), temperature \(next.temperature.map { "\($0)" } ?? "-")")
                options = next
            }
        }
        return try await send(messages, to: url, config: config, options: options, timeout: timeout)
    }

    /// One tiny request, for the settings window. Returns the round trip and the reasoning level in use.
    static func ping(_ config: LLMConfig) async throws -> (seconds: TimeInterval, reasoningEffort: String?) {
        let started = Date()
        _ = try await complete(
            [["role": "system", "content": "Reply with: ok"], ["role": "user", "content": "ok"]],
            config: config,
            timeout: 20
        )
        let saved = endpoint(for: config.baseURL).flatMap { RequestOptions.saved(for: storageKey($0, config.model)) }
        return (Date().timeIntervalSince(started), saved?.reasoningEffort)
    }

    private static func storageKey(_ url: URL, _ model: String) -> String {
        "\(url.absoluteString)|\(model)"
    }

    // MARK: Request options

    /// Optional request fields, adjusted per endpoint and model and remembered.
    ///
    /// Reasoning models (gpt-5, o-series, Gemini 2.5, Muse Spark …) think before answering unless told
    /// otherwise; left at their default, a one-line cleanup can take 10–30 s. We ask for the lowest
    /// `reasoning_effort` the model accepts: `none`, then `minimal`, then `low`, then leave it out.
    /// Models that reject a field answer with a fast 400, and the result is saved for next time.
    struct RequestOptions: Codable, Equatable {
        var temperature: Double? = 0.2
        var reasoningEffort: String? = "none"

        private static let efforts = ["none", "minimal", "low"]
        private static let storeKey = "llm.requestOptions"

        /// What to try after the server rejected these options with `message`, or nil to give up.
        func adjusted(after message: String) -> RequestOptions? {
            let text = message.lowercased()
            var next = self
            // "'temperature' is not supported with reasoning models" names both; temperature is the problem.
            if temperature != nil, text.contains("temperature") {
                next.temperature = nil
                return next
            }
            if let effort = reasoningEffort, text.contains("reasoning") || text.contains("effort") {
                // "'none' is not supported. Supported values: minimal, low…" → step down.
                // "Unrecognized request argument: reasoning_effort" → leave the field out.
                if text.contains(effort), let index = Self.efforts.firstIndex(of: effort), index + 1 < Self.efforts.count {
                    next.reasoningEffort = Self.efforts[index + 1]
                } else {
                    next.reasoningEffort = nil
                }
                return next
            }
            if temperature != nil || reasoningEffort != nil {
                return RequestOptions(temperature: nil, reasoningEffort: nil)
            }
            return nil
        }

        static func saved(for key: String) -> RequestOptions? {
            guard let data = (UserDefaults.standard.dictionary(forKey: storeKey) as? [String: Data])?[key] else { return nil }
            return try? JSONDecoder().decode(RequestOptions.self, from: data)
        }

        func save(for key: String) {
            var table = (UserDefaults.standard.dictionary(forKey: Self.storeKey) as? [String: Data]) ?? [:]
            guard let data = try? JSONEncoder().encode(self), table[key] != data else { return }
            table[key] = data
            UserDefaults.standard.set(table, forKey: Self.storeKey)
        }
    }

    // MARK: Transport

    private static func send(_ messages: [Message], to url: URL, config: LLMConfig, options: RequestOptions, timeout: TimeInterval) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = ["model": config.model, "messages": messages, "stream": false]
        if let temperature = options.temperature { body["temperature"] = temperature }
        if let effort = options.reasoningEffort { body["reasoning_effort"] = effort }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let started = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw Failure.network(error.code)
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data)
        let payload = (json as? [String: Any]) ?? (json as? [[String: Any]])?.first
        Log.info(String(format: "llm %d in %.2fs (reasoning_effort %@)", code, Date().timeIntervalSince(started), options.reasoningEffort ?? "-"))
        guard (200..<300).contains(code) else {
            throw Failure.http(code, errorMessage(in: payload, raw: data))
        }
        guard let text = replyText(in: payload) else { throw Failure.emptyReply }
        return text
    }

    private static func replyText(in payload: [String: Any]?) -> String? {
        guard let choices = payload?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else { return nil }
        if let text = message["content"] as? String { return text }
        if let parts = message["content"] as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String }.joined()
        }
        return nil
    }

    private static func errorMessage(in payload: [String: Any]?, raw: Data) -> String? {
        if let error = payload?["error"] as? [String: Any], let message = error["message"] as? String { return message }
        if let message = payload?["error"] as? String { return message }
        if let message = payload?["message"] as? String { return message }
        let text = String(decoding: raw.prefix(600), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
