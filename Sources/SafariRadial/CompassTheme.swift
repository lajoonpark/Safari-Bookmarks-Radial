import AppKit
import SwiftUI

/// The compass's materials.
///
/// Every colour here was measured, not eyeballed, because the dial is read in a glance at an
/// arbitrary place on someone's screen. Ratios in the comments are against the surface the ink
/// is actually printed on, using the same WCAG formula the rest of the app's palette is set by.
///
/// The one rule borrowed from the old instrument theme: exactly one saturated colour (the
/// vermilion needle) and it is only ever used for what you are aiming at. Everything else is
/// paper, brass, or the ink that sits on them.
enum CompassTheme {

    // MARK: - Paper

    /// The card itself. Aged cream, never white: white paper reads as a new print.
    static let paper = NSColor(calibratedRed: 0.863, green: 0.804, blue: 0.667, alpha: 1)
    /// Where the light falls on it.
    static let paperLit = NSColor(calibratedRed: 0.918, green: 0.867, blue: 0.745, alpha: 1)
    /// Aged, toward the rim.
    static let paperDeep = NSColor(calibratedRed: 0.741, green: 0.659, blue: 0.494, alpha: 1)
    /// The browned edge where card meets brass.
    static let paperEdge = NSColor(calibratedRed: 0.529, green: 0.439, blue: 0.290, alpha: 1)

    // MARK: - Ink

    /// Slice names. 9.3:1 on `paper`, 6.3:1 on the aged rim.
    static let ink = NSColor(calibratedRed: 0.200, green: 0.149, blue: 0.102, alpha: 1)
    /// Host names. 6.9:1 on `paper`, 4.7:1 on the aged rim.
    static let inkSubtle = NSColor(calibratedRed: 0.286, green: 0.231, blue: 0.157, alpha: 1)
    /// The printed degree scale and the engraved rules. Decoration, so it may sit lower.
    static let inkRule = NSColor(calibratedRed: 0.227, green: 0.173, blue: 0.102, alpha: 1)

    // MARK: - Signal

    /// The needle, the aimed numeral, the aimed wedge's rule. Deep vermilion rather than the
    /// old orange: 5.0:1 on `paper` and 5.9:1 on the numeral gate, where orange managed 2.3:1
    /// on the old hovered fill and made the aimed label the least readable thing on screen.
    static let vermilion = NSColor(calibratedRed: 0.561, green: 0.196, blue: 0.133, alpha: 1)
    /// A lighter vermilion for the needle's lit edge, where it is a line rather than ink.
    static let vermilionLit = NSColor(calibratedRed: 0.706, green: 0.267, blue: 0.180, alpha: 1)

    // MARK: - Brass

    /// Tarnished, not polished. Highlights stay warm rather than white and the shadows go
    /// olive rather than chocolate, which is the difference between "carried for years" and
    /// "polished this morning".
    static let brassHi = NSColor(calibratedRed: 0.890, green: 0.816, blue: 0.635, alpha: 1)
    static let brassLit = NSColor(calibratedRed: 0.776, green: 0.643, blue: 0.412, alpha: 1)
    static let brassMid = NSColor(calibratedRed: 0.604, green: 0.475, blue: 0.275, alpha: 1)
    static let brassDark = NSColor(calibratedRed: 0.416, green: 0.322, blue: 0.188, alpha: 1)
    static let brassDeep = NSColor(calibratedRed: 0.224, green: 0.188, blue: 0.118, alpha: 1)
    /// The olive-grey bloom of age on brass. Not rust: this is a cool, matte film.
    static let patina = NSColor(calibratedRed: 0.290, green: 0.282, blue: 0.196, alpha: 1)

    /// Inside the lid: smoke-stained and darker than the case.
    static let lidRecessInner = NSColor(calibratedRed: 0.427, green: 0.353, blue: 0.220, alpha: 1)
    static let lidRecessOuter = NSColor(calibratedRed: 0.200, green: 0.161, blue: 0.102, alpha: 1)

    // MARK: - Hub

    /// The readout window in the centre boss. 10.3:1 for `brassHi` on it, so the aimed slot
    /// number is the most legible thing on the instrument.
    static let hubWindow = NSColor(calibratedRed: 0.180, green: 0.129, blue: 0.075, alpha: 1)
    static let hubWindowInk = NSColor(calibratedRed: 0.929, green: 0.878, blue: 0.749, alpha: 1)

    // MARK: - Backdrop

    /// The scrim under the instrument. Warm and dark, never neutral grey.
    static let shadow = NSColor(calibratedRed: 0.075, green: 0.059, blue: 0.039, alpha: 1)
    static let backdropAlpha: CGFloat = 0.90
    static let backdropMidAlpha: CGFloat = 0.62

    // MARK: - Type

    /// A serif for anything printed on the card.
    ///
    /// Baskerville ships on every Mac and is the face the reference photo's card is lettered
    /// in. Palatino is the fallback, then Times, so this degrades rather than failing if a
    /// machine is trimmed down.
    static func serif(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        let candidates: [String]
        switch weight {
        case .bold, .heavy, .black:
            candidates = ["Baskerville-SemiBold", "Baskerville-Bold", "Palatino-Bold"]
        case .semibold, .medium:
            candidates = ["Baskerville-SemiBold", "Baskerville", "Palatino-Roman"]
        default:
            candidates = ["Baskerville", "Palatino-Roman", "TimesNewRomanPSMT"]
        }
        for name in candidates {
            if let font = NSFont(name: name, size: size) { return font }
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    // MARK: - Printing

    /// Degrees between the card's scale ticks.
    static let scaleStepDegrees = 5
    /// Half-width of the clear gate cut through the tick ring for each slate numeral, as a
    /// fraction of one slice's arc. Real compass cards interrupt the scale the same way.
    static let numeralGateHalf: CGFloat = 0.30
}

/// The same materials, for SwiftUI.
///
/// `CompassTheme` is an `NSColor` palette because the instrument is drawn on an `NSView` canvas.
/// The manager's mini dial and the welcome art are SwiftUI `Canvas`es, whose `GraphicsContext`
/// refuses anything but `Color`, and there is no implicit conversion between the two on Darwin.
///
/// Alpha is a parameter rather than `.opacity(…)` on purpose: `opacity(_:)` is SwiftUI's, so
/// `NSColor.opacity(0.3)` does not compile — the shade has to be applied with
/// `withAlphaComponent` before the colour crosses over.
extension NSColor {
    func swiftUI(alpha: CGFloat = 1) -> Color {
        Color(nsColor: alpha >= 1 ? self : withAlphaComponent(alpha))
    }
}
