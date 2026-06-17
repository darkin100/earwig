import Foundation

/// A piece of user feedback composed in the in-app feedback form and sent via `ResendClient`.
struct Feedback: Equatable {
    /// Quick sentiment, shown as a smiley toggle.
    enum Mood: String, CaseIterable, Identifiable {
        case happy
        case unhappy

        var id: String { rawValue }
        var symbol: String { self == .happy ? "face.smiling" : "face.dashed" }
        var label: String { self == .happy ? "Happy" : "Unhappy" }
    }

    /// What kind of feedback this is.
    enum Category: String, CaseIterable, Identifiable {
        case general
        case bug
        case feature

        var id: String { rawValue }
        var label: String {
            switch self {
            case .general: return "General"
            case .bug: return "Report a bug"
            case .feature: return "Suggest a feature"
            }
        }
    }

    var mood: Mood
    var category: Category
    var message: String
    var contactEmail: String

    var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedEmail: String {
        contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A message with actual content is the only requirement for sending.
    var isValid: Bool { !trimmedMessage.isEmpty }
}
