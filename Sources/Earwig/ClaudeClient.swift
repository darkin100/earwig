import Foundation

/// Client for Anthropic's Messages API. Key read from `SecretStore` at call time.
struct ClaudeClient: Sendable {
    static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    static let anthropicVersion = "2023-06-01"

    var model: String
    var maxTokens: Int = 2048

    init(model: String, maxTokens: Int = 2048) {
        self.model = model
        self.maxTokens = maxTokens
    }

    // MARK: - Errors

    enum ClaudeError: Error, LocalizedError {
        case noKey
        case http(Int, String)
        case decode(String)

        var errorDescription: String? {
            switch self {
            case .noKey:
                return "No Anthropic API key found. Add your key in Settings to use Claude."
            case .http(let code, _) where code == 429:
                return "Claude is currently rate limited. Please wait a moment and try again."
            case .http(let code, let message):
                return message.isEmpty ? "Anthropic returned an error (HTTP \(code))." : message
            case .decode(let message):
                return "Could not read the response from Claude: \(message)"
            }
        }
    }

    // MARK: - Request body (pure / testable)

    struct RequestBody: Encodable, Equatable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]

        struct Message: Encodable, Equatable {
            let role: String
            let content: String
        }
    }

    /// Anthropic error shape: `{"error":{"message":"..."}}`. Falls back to raw text.
    static func errorMessage(from data: Data) -> String {
        struct ErrorEnvelope: Decodable { let error: Inner; struct Inner: Decodable { let message: String } }
        if let env = try? JSONDecoder().decode(ErrorEnvelope.self, from: data), !env.error.message.isEmpty {
            return env.error.message
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func requestBody(model: String, system: String,
                            prompt: String, maxTokens: Int) -> RequestBody {
        RequestBody(
            model: model,
            max_tokens: maxTokens,
            system: system,
            messages: [.init(role: "user", content: prompt)]
        )
    }

    // MARK: - Completion

    func complete(system: String, prompt: String) async throws -> String {
        guard let key = SecretStore.anthropicKey else {
            throw ClaudeError.noKey
        }
        let body = Self.requestBody(model: model, system: system, prompt: prompt, maxTokens: maxTokens)
        var req = URLRequest(url: Self.apiURL)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.timeoutInterval = 180
        req.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw ClaudeError.http(-1, error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClaudeError.http(http.statusCode, Self.errorMessage(from: data))
        }

        // Decode { "content": [{ "type": "text", "text": "..." }] }
        struct Response: Decodable {
            let content: [ContentBlock]
            struct ContentBlock: Decodable {
                let text: String
            }
        }
        do {
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            return decoded.content.map(\.text).joined()
        } catch {
            throw ClaudeError.decode("\(error)")
        }
    }
}
