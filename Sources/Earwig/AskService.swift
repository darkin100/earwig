import Foundation

// MARK: - Result type

/// Answer to a question about past meetings, with the meeting IDs used as context.
struct AskResult: Equatable {
    let answer: String
    let sources: [String]   // meetingIds of docs included in the context
}

// MARK: - Service

/// Routes a natural-language question through the configured summary engine.
enum AskService {
    // MARK: - Context budget

    /// Max meeting-text characters in the context. Claude gets a large window; local engines are kept small.
    static func contextBudget(for engine: SummaryEngineKind) -> Int {
        engine == .claude ? 150_000 : 8_000
    }

    // MARK: - Prompt assembly

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    static func prompt(question: String, docs: [SearchDoc]) -> (system: String, user: String) {
        let system = """
            You answer questions about the user's past meetings. \
            Be concise and factual. \
            Only use the provided context. \
            If the answer is not in the context, say you could not find it.
            """

        let chunks = docs.map { doc -> String in
            let dateString = dateFormatter.string(from: doc.date)
            return """
                [Meeting: \(doc.title) - \(dateString)]
                Summary: \(doc.summary)
                Transcript: \(doc.transcript)
                """
        }

        let contextBlock = chunks.joined(separator: "\n\n")
        let user = contextBlock + "\n\nQuestion: \(question)"

        return (system: system, user: user)
    }

    // MARK: - Ask

    /// Runs `question` through `engine` with `docs` as context. Returns immediately when `docs` is empty.
    static func ask(
        question: String,
        docs: [SearchDoc],
        engine: SummaryEngineKind,
        modelID: String,
        claudeModel: String
    ) async throws -> AskResult {
        guard !docs.isEmpty else {
            return AskResult(
                answer: "I couldn't find anything about that in your meetings.",
                sources: []
            )
        }

        let (system, user) = prompt(question: question, docs: docs)

        let answer: String
        switch engine {
        case .ollama:
            // Ollama chat API has no separate system role — prepend to user message.
            answer = try await OllamaClient().chatText(
                model: modelID,
                prompt: system + "\n\n" + user
            )
        case .apple:
            answer = try await AppleSummaryEngine.respond(to: system + "\n\n" + user)
        case .claude:
            answer = try await ClaudeClient(model: claudeModel).complete(
                system: system,
                prompt: user
            )
        }

        let sources = docs.map(\.meetingId)
        return AskResult(answer: answer, sources: sources)
    }
}
