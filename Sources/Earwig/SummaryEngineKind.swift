import Foundation

enum SummaryEngineKind: String, CaseIterable, Identifiable, Sendable {
    case ollama
    case apple
    case claude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .apple: return "Apple Intelligence"
        case .claude: return "Claude"
        }
    }

    var blurb: String {
        switch self {
        case .ollama:
            return "Local Ollama models. Works on Apple Silicon and Intel. You install Ollama and pick a model."
        case .apple:
            return "Apple's built in model. Nothing to download, but it needs macOS 26 on Apple Silicon."
        case .claude:
            return "Cloud, best quality. Sends your transcript text to Anthropic."
        }
    }

    func availability() -> SummaryAvailability {
        switch self {
        case .ollama:
            return .ready
        case .apple:
            return AppleSummaryEngine.availability()
        case .claude:
            if SecretStore.anthropicKey != nil {
                return .ready
            }
            return .needsSetup("Add your Anthropic API key below.")
        }
    }

    static func from(_ raw: String) -> SummaryEngineKind {
        SummaryEngineKind(rawValue: raw) ?? .ollama
    }
}

enum SummaryAvailability: Equatable {
    case ready
    case needsSetup(String)

    var isReady: Bool { self == .ready }
}

enum SummaryEngineError: Error, LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let m): return m
        }
    }
}
