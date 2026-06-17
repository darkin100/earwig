import SwiftUI

/// Per-engine branding for the Summary engine picker: a symbol and a gradient tile colour that
/// nods to each engine's identity (Apple logo, Anthropic coral, local-compute charcoal).
extension SummaryEngineKind {
    var icon: String {
        switch self {
        case .ollama: return "cpu"
        case .apple: return "apple.logo"
        case .claude: return "sparkle"
        }
    }

    var brandGradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .ollama:
            colors = [Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255),
                      Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255)]
        case .apple:
            colors = [Color(red: 0xFF / 255, green: 0x5F / 255, blue: 0xA2 / 255),
                      Color(red: 0xA4 / 255, green: 0x5C / 255, blue: 0xFF / 255),
                      Color(red: 0x3E / 255, green: 0x8B / 255, blue: 0xFF / 255)]
        case .claude:
            colors = [Color(red: 0xE3 / 255, green: 0xA0 / 255, blue: 0x7A / 255),
                      Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
