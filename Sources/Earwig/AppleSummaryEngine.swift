import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Wraps Apple Foundation Models (macOS 26+, Apple Silicon) as a summary backend.
/// Guarded so the app still builds and runs on macOS 15 (engine reported unavailable).
enum AppleSummaryEngine {
    static func availability() -> SummaryAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .ready
            case .unavailable(let reason):
                return .needsSetup(describe(reason))
            @unknown default:
                return .needsSetup("Apple Intelligence is unavailable on this Mac.")
            }
        } else {
            return .needsSetup("Apple Intelligence needs macOS 26 or later.")
        }
        #else
        return .needsSetup("Apple Intelligence isn't available in this build.")
        #endif
    }

    static func respond(to prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let session = LanguageModelSession()
            return try await session.respond(to: prompt).content
        }
        #endif
        throw SummaryEngineError.unavailable("Apple Intelligence isn't available on this Mac.")
    }

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "This Mac doesn't support Apple Intelligence (it needs Apple Silicon)."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in System Settings to use this engine."
        case .modelNotReady:
            return "Apple Intelligence is still preparing its model. Try again shortly."
        @unknown default:
            return "Apple Intelligence is unavailable on this Mac."
        }
    }
    #endif
}
