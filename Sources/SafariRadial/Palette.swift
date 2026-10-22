import AppKit
import SwiftUI

/// Dark, high-contrast styling so the windows feel like a sibling of the radial menu.
enum Palette {
    static let background = Color(red: 0.074, green: 0.078, blue: 0.094)
    static let surface = Color(red: 0.119, green: 0.125, blue: 0.150)
    static let surfaceRaised = Color(red: 0.155, green: 0.163, blue: 0.192)
    static let stroke = Color.white.opacity(0.09)
    static let accent = Color(red: 0.36, green: 0.55, blue: 0.95)
    static let accentWarm = Color(red: 0.88, green: 0.36, blue: 0.40)
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.52)
    static let tertiaryText = Color.white.opacity(0.34)
    static let danger = Color(red: 0.94, green: 0.38, blue: 0.42)
    static let success = Color(red: 0.36, green: 0.80, blue: 0.58)
}

extension View {
    /// Rounded panel with a hairline border, used for cards throughout.
    func cardStyle(radius: CGFloat = 12) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Palette.stroke, lineWidth: 1)
        )
    }
}

/// Springy button that scales under the pointer. Small thing, but it makes the window feel alive.
struct SpringyButtonStyle: ButtonStyle {
    var tint: Color = Palette.surfaceRaised
    var foreground: Color = Palette.primaryText

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Palette.stroke, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

/// Primary call to action, with a warm accent so it reads as "do this next".
struct AccentButtonStyle: ButtonStyle {
    var isEnabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Palette.accent, Palette.accent.opacity(0.78)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .opacity(isEnabled ? 1 : 0.35)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
