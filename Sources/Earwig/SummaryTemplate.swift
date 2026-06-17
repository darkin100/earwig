import Foundation

struct SummaryTemplate: Identifiable, Equatable {
    let id: String
    let name: String
    let instructions: String
}

extension SummaryTemplate {
    static let dailyStandup = SummaryTemplate(
        id: "daily-standup",
        name: "Daily team meeting",
        instructions: """
        This is a daily team meeting (e.g. a Microsoft Teams stand-up). Summarize what each \
        participant reported: progress since last time, plans for today, and any blockers. \
        Capture decisions and concrete action items with an owner where stated.
        """)

    static let oneOnOne = SummaryTemplate(
        id: "one-on-one",
        name: "1:1",
        instructions: """
        This is a one-on-one conversation. Summarize the main topics discussed, any feedback \
        exchanged, agreements reached, and follow-ups with owners.
        """)

    static let general = SummaryTemplate(
        id: "general-meeting",
        name: "General meeting",
        instructions: """
        Summarize this meeting for someone who missed it: the purpose, the key points raised, \
        decisions made, and action items with owners.
        """)

    static let actionItemsOnly = SummaryTemplate(
        id: "action-items-only",
        name: "Action items only",
        instructions: """
        Extract only the concrete action items and decisions from this meeting. Keep the TL;DR \
        to one sentence and leave keyPoints empty unless essential.
        """)

    static let builtIns: [SummaryTemplate] = [dailyStandup, oneOnOne, general, actionItemsOnly]
    static let defaultID = dailyStandup.id

    static func byID(_ id: String) -> SummaryTemplate {
        builtIns.first { $0.id == id } ?? dailyStandup
    }

    func prompt(for transcript: String, custom: String = "", notes: String = "") -> String {
        let guidance = custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? instructions : custom
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesSuffix = trimmedNotes.isEmpty ? "" : """


        The attendee also wrote these notes. Treat them as important context and make sure the summary reflects them:
        \(trimmedNotes)
        """
        return """
        You are an expert meeting note-taker. \(guidance)

        Respond with ONLY a JSON object (no prose, no code fences) of exactly this shape:
        {"tldr": "1-2 sentence overview", "keyPoints": ["..."], "decisions": ["..."], \
        "actionItems": [{"owner": "name or null", "task": "..."}]}
        Use [] for empty lists. Use the speakers' names as owners when known.\(notesSuffix)

        Transcript:
        \(transcript)
        """
    }
}
