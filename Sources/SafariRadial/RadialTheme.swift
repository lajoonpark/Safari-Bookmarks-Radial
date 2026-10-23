import AppKit

/// Visual constants for the radial dial.
///
/// The dial has one job: show you which of nine things you are about to open. So the
/// structure is borrowed from a machined instrument — an engraved bezel with a tick scale
/// and slot numbers, wedges that lift off the surface along their own bearing when aimed at,
/// and a hub that reads back the number you are pointing at.
enum RadialTheme {
    static let hubDiameter: CGFloat = 112

    // Bezel
    static let bezelTickCount = 60
    static let bezelTickInnerGap: CGFloat = 10
    static let bezelMinorTick: CGFloat = 4
    static let bezelMajorTick: CGFloat = 9
    /// Width of the printed number band just outside the tick scale.
    static let bezelBandWidth: CGFloat = 20
    static let bezelBandInset: CGFloat = 21
    static let bezelBandFill = NSColor(calibratedRed: 0.012, green: 0.047, blue: 0.059, alpha: 0.72)

    // Slice body: cold glass, deepest at the hub so the ring reads as a lit dial.
    static let sliceNear = NSColor(calibratedRed: 0.035, green: 0.110, blue: 0.129, alpha: 0.97)
    static let sliceMid = NSColor(calibratedRed: 0.059, green: 0.153, blue: 0.176, alpha: 0.97)
    static let sliceFar = NSColor(calibratedRed: 0.075, green: 0.180, blue: 0.204, alpha: 0.97)

    static let sliceNearHover = NSColor(calibratedRed: 0.078, green: 0.235, blue: 0.251, alpha: 1)
    static let sliceMidHover = NSColor(calibratedRed: 0.122, green: 0.314, blue: 0.322, alpha: 1)
    static let sliceFarHover = NSColor(calibratedRed: 0.243, green: 0.361, blue: 0.337, alpha: 1)

    static let sliceStroke = NSColor(white: 1, alpha: 0.10)
    static let sliceStrokeHover = NSColor(calibratedRed: 1.0, green: 0.420, blue: 0.173, alpha: 0.72)

    // Hub
    static let hubFillTop = NSColor(calibratedRed: 0.055, green: 0.141, blue: 0.161, alpha: 1)
    static let hubFillBottom = NSColor(calibratedRed: 0.020, green: 0.067, blue: 0.078, alpha: 1)
    static let hubFillTopHover = NSColor(calibratedRed: 0.157, green: 0.082, blue: 0.055, alpha: 1)
    static let hubFillBottomHover = NSColor(calibratedRed: 0.078, green: 0.043, blue: 0.031, alpha: 1)
    static let hubBorder = NSColor(white: 1, alpha: 0.14)
    static let hubReadoutDisc = NSColor(calibratedRed: 0.020, green: 0.063, blue: 0.075, alpha: 0.94)

    // Ink
    static let titleInk = NSColor(calibratedRed: 0.949, green: 0.918, blue: 0.863, alpha: 0.95)
    static let titleInkHover = NSColor(calibratedRed: 0.988, green: 0.965, blue: 0.925, alpha: 1)
    static let subtitleInk = NSColor(calibratedRed: 0.949, green: 0.918, blue: 0.863, alpha: 0.46)
    static let subtitleInkHover = NSColor(calibratedRed: 1.0, green: 0.420, blue: 0.173, alpha: 0.88)
    /// Slot numbers sit on the band outside the ring, so they have to hold up against a
    /// blurred desktop behind them — the old 0.38 read as a smudge on a bright wallpaper.
    static let bezelNumberInk = NSColor(calibratedRed: 0.949, green: 0.918, blue: 0.863, alpha: 0.78)
    /// Warm light that spills out from behind the aimed wedge.
    static let aimGlowAlpha: CGFloat = 0.13
    static let bezelTickInk = NSColor(calibratedRed: 0.949, green: 0.918, blue: 0.863, alpha: 0.11)
    static let bezelTickMajorInk = NSColor(calibratedRed: 0.949, green: 0.918, blue: 0.863, alpha: 0.30)
    static let signal = NSColor(calibratedRed: 1.0, green: 0.420, blue: 0.173, alpha: 1)
    static let footerInk = NSColor(calibratedRed: 0.949, green: 0.918, blue: 0.863, alpha: 0.42)

    // Backdrop: dims under the dial only, so it stays an overlay rather than a modal.
    static let backdropInner = NSColor(calibratedRed: 0.012, green: 0.035, blue: 0.043, alpha: 1)
    static let backdropAlpha: CGFloat = 0.78
    static let backdropMidAlpha: CGFloat = 0.42

    /// How far an aimed wedge lifts off the surface.
    static let hoverLift: CGFloat = 7
    /// Radius offset of the label, so the label rises with its wedge.
    static let labelLift: CGFloat = 4

    static func titleFont(size: CGFloat, weight: NSFont.Weight = .semibold) -> NSFont {
        Palette.nsDisplay(size, weight)
    }

    static func subtitleFont(size: CGFloat) -> NSFont {
        Palette.nsMono(size, .regular)
    }

    static func bezelFont(size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont {
        Palette.nsMono(size, weight)
    }
}
