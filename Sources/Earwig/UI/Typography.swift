import SwiftUI

/// Typography scale — big, clear, Apple-like. System SF (Dynamic Type friendly via `.system`
/// sizes). Hierarchy is generous so the light layout breathes. Section titles are uppercased +
/// tracked by `SectionHeader`.
extension Font {
    /// Page heroes — "Meetings", onboarding title.
    static let pageTitle = Font.system(size: 34, weight: .bold)
    /// Large section / day headers.
    static let sectionLarge = Font.system(size: 20, weight: .bold)
    /// Hairline section headers (uppercased + tracked by `SectionHeader`).
    static let sectionTitle = Font.system(size: 13, weight: .semibold)
    /// Row titles — meeting/person/model names.
    static let rowTitle = Font.system(size: 17, weight: .semibold)
    /// Body, transcript, summary text.
    static let bodyText = Font.system(size: 15, weight: .regular)
    /// Field labels and button text.
    static let label = Font.system(size: 14, weight: .medium)
    /// Meta lines, timestamps, hints.
    static let captionText = Font.system(size: 13, weight: .regular)
}
