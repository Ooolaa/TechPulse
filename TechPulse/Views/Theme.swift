import SwiftUI

/// Design tokens lifted from design/TechPulse_Screens.dc.html.
/// One type family (system/SF); mastery states carry the only color:
/// gray = new, blue = learning, green = known.
enum Theme {
    static let background = Color(hex: 0xF6F7F9)
    static let card = Color.white
    static let cardBorder = Color(hex: 0xE4E8ED)
    static let textPrimary = Color(hex: 0x17181A)
    static let textSecondary = Color(hex: 0x6B7280)
    static let textTertiary = Color(hex: 0x8A919C)

    static let stateNew = Color(hex: 0xA6ADB8)
    static let stateLearning = Color(hex: 0x3D7BE0)
    static let stateKnown = Color(hex: 0x2FA46B)

    static let learningTint = Color(hex: 0xEEF4FD)
    static let knownTint = Color(hex: 0xEAF6F0)
    static let newTint = Color(hex: 0xF1F3F6)

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
