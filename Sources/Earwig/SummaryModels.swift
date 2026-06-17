import Foundation

enum SummaryModels {
    struct Model: Equatable, Identifiable {
        let id: String
        let name: String
        let blurb: String
        let approxSizeGB: Double
    }

    static let defaultModel = Model(
        id: "qwen2.5:14b", name: "Qwen2.5 14B",
        blurb: "Higher-quality on-device summaries, much closer to cloud models. Downloads once "
            + "(about 9 GB) and runs offline. Best on Macs with 16 GB of memory or more.",
        approxSizeGB: 9.0)

    static let catalog: [Model] = [defaultModel]

    // Weaker models shipped as defaults in earlier versions; silently upgrade to current default.
    static let legacyIDs: Set<String> = ["llama3.1:8b", "llama3.2:3b", "qwen2.5:3b"]

    static func model(for id: String) -> Model {
        if legacyIDs.contains(id) { return defaultModel }
        return catalog.first { $0.id == id } ?? defaultModel
    }

    /// Unknown non-empty tags are kept as custom models (user-pulled).
    static func resolved(override: String = "") -> Model {
        if override.isEmpty || legacyIDs.contains(override) { return defaultModel }
        if let known = catalog.first(where: { $0.id == override }) { return known }
        return Model(id: override, name: override, blurb: "Custom Ollama model", approxSizeGB: 0)
    }
}
