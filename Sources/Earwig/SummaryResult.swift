import Foundation

struct ActionItem: Codable, Equatable {
    let owner: String?
    let task: String
}

struct SummaryResult: Codable, Equatable {
    var tldr: String
    var keyPoints: [String]
    var decisions: [String]
    var actionItems: [ActionItem]

    var isEmpty: Bool {
        tldr.isEmpty && keyPoints.isEmpty && decisions.isEmpty && actionItems.isEmpty
    }
}

extension SummaryResult {
    /// Extracts the first balanced `{ }` from raw model output and decodes it leniently.
    static func parse(_ raw: String) -> SummaryResult? {
        guard let jsonString = firstJSONObject(in: raw),
              let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let tldr = (obj["tldr"] as? String) ?? ""
        let keyPoints = (obj["keyPoints"] as? [Any])?.compactMap { $0 as? String } ?? []
        let decisions = (obj["decisions"] as? [Any])?.compactMap { $0 as? String } ?? []
        let actionItems = (obj["actionItems"] as? [[String: Any]])?.compactMap { dict -> ActionItem? in
            guard let task = dict["task"] as? String, !task.isEmpty else { return nil }
            let owner = dict["owner"] as? String
            return ActionItem(owner: (owner?.isEmpty ?? true) ? nil : owner, task: task)
        } ?? []
        let result = SummaryResult(
            tldr: tldr, keyPoints: keyPoints, decisions: decisions, actionItems: actionItems)
        return result.isEmpty ? nil : result
    }

    private static func firstJSONObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0, inString = false, escaped = false
        var idx = start
        while idx < text.endIndex {
            let ch = text[idx]
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
            } else if ch == "\"" {
                inString = true
            } else if ch == "{" {
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0 { return String(text[start...idx]) }
            }
            idx = text.index(after: idx)
        }
        return nil
    }
}
