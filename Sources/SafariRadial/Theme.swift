import AppKit

/// Visual constants for the radial menu.
enum Theme {
    static let panelPadding: CGFloat = 90
    static let hubDiameter: CGFloat = 96

    // Slices
    static let sliceFillTop = NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.21, alpha: 0.92)
    static let sliceFillBottom = NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.14, alpha: 0.92)
    static let sliceFillHoverTop = NSColor(calibratedRed: 0.29, green: 0.42, blue: 0.68, alpha: 0.97)
    static let sliceFillHoverBottom = NSColor(calibratedRed: 0.20, green: 0.30, blue: 0.55, alpha: 0.97)
    static let sliceBorder = NSColor(white: 1, alpha: 0.10)
    static let sliceBorderHover = NSColor(white: 1, alpha: 0.45)
    static let sliceSeparator = NSColor(white: 1, alpha: 0.06)

    // Hub
    static let hubFill = NSColor(calibratedWhite: 0.08, alpha: 0.96)
    static let hubFillHover = NSColor(calibratedRed: 0.62, green: 0.20, blue: 0.24, alpha: 0.98)
    static let hubBorder = NSColor(white: 1, alpha: 0.16)
    static let hubGlyph = NSColor(white: 1, alpha: 0.82)

    // Text
    static let titleColor = NSColor(white: 1, alpha: 0.96)
    static let titleColorHover = NSColor.white
    static let subtitleColor = NSColor(white: 1, alpha: 0.52)
    static let badgeTextColor = NSColor(white: 1, alpha: 0.92)
    static let badgeFill = NSColor(white: 1, alpha: 0.13)
    static let badgeFillHover = NSColor(white: 1, alpha: 0.24)
    static let footerColor = NSColor(white: 1, alpha: 0.42)

    // Backdrop behind the whole ring
    static let backdropCenter = NSColor(calibratedWhite: 0.10, alpha: 0.55)
    static let backdropEdge = NSColor(calibratedWhite: 0.05, alpha: 0.0)

    static func titleFont(size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    static func subtitleFont(size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .regular)
    }

    static func badgeFont(size: CGFloat) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
    }
}
