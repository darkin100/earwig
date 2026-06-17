import SwiftUI

/// The tabs shown for a selected meeting.
enum MeetingTab: String, CaseIterable, Identifiable {
    case summary
    case transcript
    case notes
    case actionItems
    case details

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary: return "Summary"
        case .transcript: return "Transcript"
        case .notes: return "Notes"
        case .actionItems: return "Actions"
        case .details: return "Details"
        }
    }

    var symbol: String {
        switch self {
        case .summary: return "sparkles"
        case .transcript: return "text.alignleft"
        case .notes: return "square.and.pencil"
        case .actionItems: return "checklist"
        case .details: return "info.circle"
        }
    }
}
