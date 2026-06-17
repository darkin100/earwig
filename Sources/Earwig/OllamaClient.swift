import Foundation

/// Minimal Ollama client: list models, JSON chat, model pull. Pure URLSession, no dependencies.
struct OllamaClient: Sendable {
    struct Model: Equatable, Sendable, Identifiable {
        let name: String       // Ollama tag, e.g. "qwen2.5:3b"
        let sizeBytes: Int64
        var id: String { name }
    }

    enum OllamaError: Error, LocalizedError {
        case notRunning
        case http(Int, String)
        case decode(String)
        case modelMissing(String)

        var errorDescription: String? {
            switch self {
            case .notRunning:
                return "Ollama isn't running. Install it from ollama.com and make sure the Ollama app is open."
            case .http(let code, let body):
                return "Ollama returned HTTP \(code): \(body)"
            case .decode(let m):
                return "Couldn't read Ollama's response: \(m)"
            case .modelMissing(let m):
                return "The model \"\(m)\" isn't installed. Pull it first: ollama pull \(m)"
            }
        }
    }

    static let defaultEndpoint = URL(string: "http://localhost:11434")!

    var endpoint: URL = OllamaClient.defaultEndpoint

    // MARK: - Request body (pure / testable)

    struct ChatRequest: Encodable, Equatable {
        let model: String
        let stream: Bool
        let format: String
        let options: Options
        let messages: [Message]

        struct Options: Encodable, Equatable {
            let temperature: Double
            let num_predict: Int
            // Ollama defaults ~4K, which silently truncates real meeting transcripts → size to prompt.
            let num_ctx: Int
        }

        struct Message: Encodable, Equatable {
            let role: String
            let content: String
        }
    }

    /// ~4 chars/token estimate, rounded up to 4K steps, clamped to [8K, 32K].
    static func contextWindow(forPrompt prompt: String, maxTokens: Int) -> Int {
        let estimated = prompt.count / 4 + maxTokens + 512
        let rounded = ((estimated / 4096) + 1) * 4096
        return min(32768, max(8192, rounded))
    }

    static func chatRequest(model: String, prompt: String,
                            temperature: Double = 0.2, maxTokens: Int = 2048,
                            json: Bool = true) -> ChatRequest {
        ChatRequest(
            model: model, stream: false, format: json ? "json" : "",
            options: .init(temperature: temperature, num_predict: maxTokens,
                           num_ctx: contextWindow(forPrompt: prompt, maxTokens: maxTokens)),
            messages: [.init(role: "user", content: prompt)])
    }

    // MARK: - Availability + models

    /// True if the daemon answers `/api/tags` quickly.
    func isReachable() async -> Bool {
        (try? await installedModels()) != nil
    }

    func installedModels() async throws -> [Model] {
        var req = URLRequest(url: endpoint.appendingPathComponent("api/tags"))
        req.timeoutInterval = 5
        let data: Data
        do {
            let (d, resp) = try await URLSession.shared.data(for: req)
            try Self.check(resp, d)
            data = d
        } catch let e as OllamaError {
            throw e
        } catch {
            throw OllamaError.notRunning
        }
        struct Tags: Decodable { let models: [Entry] }
        struct Entry: Decodable { let name: String; let size: Int64 }
        do {
            return try JSONDecoder().decode(Tags.self, from: data)
                .models.map { Model(name: $0.name, sizeBytes: $0.size) }
        } catch {
            throw OllamaError.decode("\(error)")
        }
    }

    // MARK: - Chat

    func chatJSON(model: String, prompt: String,
                  temperature: Double = 0.2, maxTokens: Int = 2048) async throws -> String {
        try await chat(model: model, prompt: prompt, temperature: temperature,
                       maxTokens: maxTokens, json: true)
    }

    // format: "" → prose response; chatJSON sets format: "json".
    func chatText(model: String, prompt: String,
                  temperature: Double = 0.2, maxTokens: Int = 1024) async throws -> String {
        try await chat(model: model, prompt: prompt, temperature: temperature,
                       maxTokens: maxTokens, json: false)
    }

    private func chat(model: String, prompt: String,
                      temperature: Double, maxTokens: Int, json: Bool) async throws -> String {
        var req = URLRequest(url: endpoint.appendingPathComponent("api/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 180
        req.httpBody = try JSONEncoder().encode(
            Self.chatRequest(model: model, prompt: prompt, temperature: temperature,
                             maxTokens: maxTokens, json: json))

        let data: Data
        do {
            let (d, resp) = try await URLSession.shared.data(for: req)
            try Self.check(resp, d, model: model)
            data = d
        } catch let e as OllamaError {
            throw e
        } catch {
            throw OllamaError.notRunning
        }
        struct Reply: Decodable { let message: Message; struct Message: Decodable { let content: String } }
        do {
            return try JSONDecoder().decode(Reply.self, from: data).message.content
        } catch {
            throw OllamaError.decode("\(error)")
        }
    }

    // MARK: - Pull (streaming progress)

    /// Streams pull progress as [0,1]; throws if daemon is unreachable.
    func pull(model: String, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        var req = URLRequest(url: endpoint.appendingPathComponent("api/pull"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "stream": true])

        let bytes: URLSession.AsyncBytes
        do {
            let (b, resp) = try await URLSession.shared.bytes(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                throw OllamaError.http((resp as? HTTPURLResponse)?.statusCode ?? -1, "pull failed")
            }
            bytes = b
        } catch let e as OllamaError {
            throw e
        } catch {
            throw OllamaError.notRunning
        }

        for try await line in bytes.lines {
            guard let d = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
            if let err = obj["error"] as? String { throw OllamaError.http(500, err) }
            if let total = obj["total"] as? Double, let done = obj["completed"] as? Double, total > 0 {
                onProgress(min(1, done / total))
            }
            if obj["status"] as? String == "success" { onProgress(1) }
        }
    }

    // MARK: - Internals

    private static func check(_ resp: URLResponse, _ data: Data, model: String? = nil) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        if http.statusCode == 404, let model { throw OllamaError.modelMissing(model) }
        guard (200..<300).contains(http.statusCode) else {
            throw OllamaError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }
}
