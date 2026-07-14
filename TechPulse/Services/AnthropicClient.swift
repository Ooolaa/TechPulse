import Foundation

/// Minimal Anthropic Messages API client — plain URLSession, no SDK, no
/// third-party code. The user's own key authorizes requests that go directly
/// to api.anthropic.com; nothing passes through any server of ours.
struct AnthropicClient {
    enum ClientError: LocalizedError {
        case badStatus(Int, String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .badStatus(let code, let body):
                code == 401 ? "The API key was rejected — check it in Settings."
                            : "Anthropic API error \(code): \(body.prefix(160))"
            case .emptyResponse: "The model returned an empty response."
            }
        }
    }

    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let model = "claude-sonnet-5"

    var session: URLSession = .shared

    private struct RequestBody: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
        struct Message: Encodable {
            let role: String
            let content: String
        }
    }

    private struct ResponseBody: Decodable {
        struct Content: Decodable { let type: String; let text: String? }
        let content: [Content]
    }

    /// One-shot completion; returns the model's text.
    func complete(system: String, user: String, maxTokens: Int = 4096,
                  apiKey: String) async throws -> String {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(RequestBody(
            model: Self.model, max_tokens: maxTokens, system: system,
            messages: [.init(role: "user", content: user)]
        ))

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ClientError.badStatus(status, String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text,
              !text.isEmpty else { throw ClientError.emptyResponse }
        return text
    }
}
