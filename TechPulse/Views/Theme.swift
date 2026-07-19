import SwiftUI
import UIKit

/// Design tokens lifted from design/TechPulse_Screens.dc.html.
/// One type family (system/SF); mastery states carry the only color:
/// gray = new, blue = learning, green = known.
///
/// Every surface/text token is adaptive (light / dark). The three mastery
/// state colors are deliberately mode-constant: they are the app's semantic
/// vocabulary, mid-tone enough to read on both chassis, and keeping them
/// identical preserves the color-blind-safe lightness ordering in both modes.
enum Theme {
    static let background = Color(light: 0xF6F7F9, dark: 0x0F1013)
    static let card = Color(light: 0xFFFFFF, dark: 0x1A1C20)
    static let cardBorder = Color(light: 0xE4E8ED, dark: 0x2A2E35)
    static let textPrimary = Color(light: 0x17181A, dark: 0xF0F1F3)
    static let textSecondary = Color(light: 0x6B7280, dark: 0x9CA3AF)
    static let textTertiary = Color(light: 0x8A919C, dark: 0x7B838F)

    static let stateNew = Color(hex: 0xA6ADB8)
    static let stateLearning = Color(hex: 0x3D7BE0)
    static let stateKnown = Color(hex: 0x2FA46B)

    static let learningTint = Color(light: 0xEEF4FD, dark: 0x1A2433)
    static let knownTint = Color(light: 0xEAF6F0, dark: 0x172A1F)
    static let newTint = Color(light: 0xF1F3F6, dark: 0x24272C)
    static let learningBorder = Color(light: 0xDCE7F8, dark: 0x2E3D54)
    static let knownBorder = Color(light: 0xD3EBDD, dark: 0x2A4A37)

    static let danger = Color(hex: 0xD9534F)
    static let dangerTint = Color(light: 0xFDF0EF, dark: 0x3A2321)

    /// Neutral inset fill: progress-bar tracks, image placeholders.
    static let track = Color(light: 0xEDF0F3, dark: 0x2A2E35)

    /// Ink scale for text ON cards, between textPrimary and textSecondary:
    /// body (article text) > strong (summaries, quiz stems) > label (captions, icons).
    static let textBody = Color(light: 0x2B2F36, dark: 0xD5D9DE)
    static let textStrong = Color(light: 0x374151, dark: 0xC6CDD6)
    static let textLabel = Color(light: 0x4B5563, dark: 0xAEB6C1)

    /// Knowledge-graph strokes (drawn in Canvas on Theme.card).
    static let graphEdge = Color(light: 0xDDE3EA, dark: 0x323843)
    static let graphEdgeDirected = Color(light: 0xD5DBE3, dark: 0x3A414C)
    static let graphArrow = Color(light: 0xC9D0D9, dark: 0x4C5460)

    /// Drop shadows stay dark in both modes (a light shadow reads as a glow).
    static let shadow = Color(hex: 0x17181A)

    static let cardRadius: CGFloat = 18
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// Trait-adaptive color from a light- and dark-mode hex pair.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

/// White card with hairline border — the base surface for every screen.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            )
    }
}

extension View {
    func techPulseCard() -> some View { modifier(CardBackground()) }
}
