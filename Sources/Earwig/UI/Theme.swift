import SwiftUI

/// Earwig's design tokens — a light, vibrant, glossy "Apple-like" system. White/very-light
/// surfaces, big clear type, generous spacing, and an indigo→purple glossy gradient for the
/// primary actions. Colour is used freely (vibrant tags/avatars) — this is the playful,
/// Jamie-inspired direction.
enum Theme {
    // MARK: - Surfaces (light)

    /// App/window background — a soft cool grey so white cards pop.
    static let bg = Color(red: 0xF2 / 255, green: 0xF3 / 255, blue: 0xF7 / 255) // #F2F3F7
    /// Card / content surface.
    static let surface = Color.white
    /// Hover / selected fill (subtle indigo tint).
    static let elevated = Color(red: 0xEC / 255, green: 0xEC / 255, blue: 0xF6 / 255) // #ECECF6
    /// Hairline dividers / subtle outlines.
    static let hairline = Color.black.opacity(0.06)

    // MARK: - Accent + gradient

    /// Primary accent — Apple indigo. Used for selection, links, small accents.
    static let accent = Color(red: 0x5E / 255, green: 0x5C / 255, blue: 0xE6 / 255) // #5E5CE6
    /// Secondary accent for gradients — violet.
    static let accent2 = Color(red: 0x9B / 255, green: 0x5C / 255, blue: 0xF6 / 255) // #9B5CF6

    /// The glossy indigo→purple gradient for primary buttons and highlights.
    static let primaryGradient = LinearGradient(
        colors: [
            Color(red: 0x63 / 255, green: 0x66 / 255, blue: 0xF1 / 255), // indigo #6366F1
            Color(red: 0x8B / 255, green: 0x5C / 255, blue: 0xF6 / 255), // violet #8B5CF6
            Color(red: 0xA8 / 255, green: 0x55 / 255, blue: 0xF7 / 255), // purple #A855F7
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Text/icon colour that sits on the accent gradient.
    static let onAccent = Color.white

    static let green = Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255)  // #30D158
    static let amber = Color(red: 0xFF / 255, green: 0x9F / 255, blue: 0x0A / 255)  // #FF9F0A
    static let danger = Color(red: 0xFF / 255, green: 0x3B / 255, blue: 0x30 / 255) // #FF3B30

    // MARK: - Text tiers (near-black on light)

    static let textPrimary = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255) // #1C1C1E
    static let textSecondary = Color(red: 0x6E / 255, green: 0x6E / 255, blue: 0x73 / 255) // #6E6E73
    static let textTertiary = Color(red: 0xA1 / 255, green: 0xA1 / 255, blue: 0xA6 / 255) // #A1A1A6

    // MARK: - Soft shadow (for glossy cards/buttons)

    static let shadow = Color.black.opacity(0.08)

    // MARK: - Avatar / tag palette (vibrant Apple system colours)

    /// Deterministic, vibrant fills. `SpeakerAvatar` hashes a label into this palette. Initials
    /// render white.
    static let avatarPalette: [Color] = [
        Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255), // blue
        Color(red: 0x5E / 255, green: 0x5C / 255, blue: 0xE6 / 255), // indigo
        Color(red: 0xBF / 255, green: 0x5A / 255, blue: 0xF2 / 255), // purple
        Color(red: 0xFF / 255, green: 0x9F / 255, blue: 0x0A / 255), // orange
        Color(red: 0xFF / 255, green: 0x37 / 255, blue: 0x5F / 255), // pink
        Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255), // green
        Color(red: 0x40 / 255, green: 0xC8 / 255, blue: 0xE0 / 255), // teal
    ]
}

/// Spacing scale on an 8-pt grid (with 4 as the half-step), plus larger steps for the airy
/// light layout.
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

/// Corner-radius family — larger, softer radii for the glossy look.
enum Radius {
    static let card: CGFloat = 20
    static let control: CGFloat = 12
    static let pill: CGFloat = 999
}
