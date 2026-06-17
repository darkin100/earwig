import Foundation

/// Routes summary generation to Ollama, Apple Foundation Models, or Claude based on Settings.
actor Summarizer {
    static let shared = Summarizer()

    enum SummarizerError: Error, LocalizedError {
        case generationFailed(String)
        case unparseable

        var errorDescription: String? {
            switch self {
            case .generationFailed(let m): return "Summary generation failed: \(m)"
            case .unparseable: return "The model did not return a usable summary."
            }
        }
    }

    // On-device models occasionally emit truncated JSON; a retry usually recovers.
    private static let maxAttempts = 3

    func summarize(transcript: String, template: SummaryTemplate, custom: String,
                   engine: SummaryEngineKind, modelID: String,
                   notes: String = "") async throws -> SummaryResult {
        let prompt = template.prompt(for: transcript, custom: custom, notes: notes)
        var lastRaw = ""
        for attempt in 1 ... Self.maxAttempts {
            let raw: String
            do {
                switch engine {
                case .ollama:
                    raw = try await OllamaClient().chatJSON(model: modelID, prompt: prompt)
                case .apple:
                    raw = try await AppleSummaryEngine.respond(to: prompt + "\n\nReturn only the JSON object.")
                case .claude:
                    raw = try await ClaudeClient(model: modelID).complete(
                        system: "You are a meeting summariser. Return only the requested JSON.",
                        prompt: prompt
                    )
                }
            } catch {
                let detail = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                throw SummarizerError.generationFailed(detail)
            }
            lastRaw = raw
            if let result = SummaryResult.parse(raw) {
                return result
            }
            Log.info("Summary parse failed (attempt \(attempt)/\(Self.maxAttempts)); raw head: \(raw.prefix(200))")
        }
        Log.info("Summary unparseable after \(Self.maxAttempts) attempts; final raw head: \(lastRaw.prefix(200))")
        throw SummarizerError.unparseable
    }
}
