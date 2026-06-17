import Foundation

struct StoredSummary: Codable, Equatable {
    let meeting: String
    let model: String
    let templateID: String
    let generatedAt: TimeInterval
    let summary: SummaryResult
}

enum SummaryStore {
    static func write(_ summary: SummaryResult, meeting: String, model: String,
                      templateID: String, generatedAt: TimeInterval, to url: URL) throws {
        let doc = StoredSummary(
            meeting: meeting, model: model, templateID: templateID,
            generatedAt: generatedAt, summary: summary)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(doc).write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> StoredSummary {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(StoredSummary.self, from: data)
    }
}
