import AppKit
import SwiftUI

/// The app's design language.
///
/// One idea drives it: this is a **brass pocket compass**, not a list of links. The surfaces
/// are the desk it lies on — warm brown-black leather and oak — the ink is aged parchment,
/// and there is one saturated colour, the vermilion needle, used only for the thing you are
/// aiming at. That is the whole palette; every other value is a shade of the desk.
///
/// The change from cold petrol is deliberate and total: a brass instrument sitting in a
/// green-glass window reads as two products. Every token here is a warm value measured
/// against the surfaces it is actually used on, using composited alpha rather than the raw
/// colour — `bone.opacity(0.56)` is not 0.56 of the way to black, and assuming so is how
/// secondary text ends up under the floor.
enum Palette {

    // MARK: - Surfaces

    /// Window background: the leather the compass sits on. Warm, never neutral grey.
    static let void = Color(red: 0.102, green: 0.078, blue: 0.063)
    static let voidRaised = Color(red: 0.141, green: 0.110, blue: 0.086)
    /// Panels, fields, rows: oak.
    static let hull = Color(red: 0.165, green: 0.129, blue: 0.102)
    static let hullLift = Color(red: 0.208, green: 0.165, blue: 0.129)
    /// Title bar gradient ends.
    static let chromeTop = Color(red: 0.165, green: 0.129, blue: 0.102)
    static let chromeBottom = Color(red: 0.122, green: 0.094, blue: 0.075)

    // MARK: - Lines

    static let rim = Color(red: 0.941, green: 0.898, blue: 0.804).opacity(0.10)
    static let rimStrong = Color(red: 0.941, green: 0.898, blue: 0.804).opacity(0.24)

    // MARK: - Ink

    /// Aged parchment rather than pure white: white on a warm desk looks dead.
    ///
    /// The opacity ladder is measured on the composited colour against `hull`/`lift`, the
    /// lightest surfaces it is drawn on. 0.62 lands at 5.8:1 on hull and 5.3:1 on lift; 0.56
    /// still clears 4.5:1 on every surface in the app, which is the floor for body text.
    static let bone = Color(red: 0.941, green: 0.898, blue: 0.804)
    /// Secondary text: subtitles, host names, help lines. 5.8:1 on `hull`.
    static let boneDim = bone.opacity(0.62)
    /// Tertiary: column headers, decorative counts. 4.95:1 on `hull`.
    static let boneFaint = bone.opacity(0.56)
    /// Placeholder text. A placeholder is the only label some fields have, so it is the one
    /// string that must never be guessed at.
    static let hint = bone.opacity(0.62)

    // MARK: - Signal

    /// The one differentiating colour: the needle's vermilion. Hover, aim, primary action.
    ///
    /// The old orange was 2.3:1 when drawn on its own hovered fill, which made the aimed
    /// label the least readable thing on screen. This clears 5.2:1 on `hull` and 4.6:1 on
    /// `hullLift`, so it may be used for text as well as for a fill.
    static let signal = Color(red: 0.851, green: 0.482, blue: 0.275)
    static let signalInk = Color(red: 0.125, green: 0.098, blue: 0.070)
    /// Confirmed / success: the patina's green, not a second accent.
    static let mint = Color(red: 0.561, green: 0.749, blue: 0.639)
    static let alarm = Color(red: 0.878, green: 0.506, blue: 0.478)

    // MARK: - Type

    /// Baskerville: the serif the reference card is lettered in, and a face that ships on
    /// every Mac. Palatino is the fallback. A serif is the whole difference between "printed
    /// instrument" and "app chrome".
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .custom("Baskerville", size: size).weight(weight)
    }

    /// Everything numeric or technical: slot numbers, keycaps, URLs, counts.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // AppKit mirrors, for the canvas-drawn radial.
    static func nsDisplay(_ size: CGFloat, _ weight: NSFont.Weight = .semibold) -> NSFont {
        let name: String
        switch weight {
        case .regular, .light, .thin, .ultraLight: name = "Baskerville"
        case .medium, .semibold: name = "Baskerville-SemiBold"
        case .bold, .heavy, .black: name = "Baskerville-Bold"
        default: name = "Baskerville"
        }
        return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func nsMono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    // AppKit colour for the radial renderer and the recorder.
    static let nsSignal = NSColor(calibratedRed: 0.851, green: 0.482, blue: 0.275, alpha: 1)
    static let nsVoid = NSColor(calibratedRed: 0.102, green: 0.078, blue: 0.063, alpha: 1)
}

/// SwiftUI's default placeholder resolves to a near-black secondary colour over this
/// palette, which made empty fields read as unlabelled boxes. Prompts are coloured here so
/// every field in the app gets a hint you can actually see.
func hint(_ text: String) -> Text {
    Text(text).foregroundColor(Palette.hint)
}

// MARK: - Shared controls

extension View {
    /// A hairline-outlined panel. Used for structural blocks, not for every row.
    func hullPanel(radius: CGFloat = 8, fill: Color = Palette.hull) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Palette.rim, lineWidth: 1)
        )
    }
}

/// Secondary action: quiet until pressed, which is where this product spends its motion.
struct QuietButtonStyle: ButtonStyle {
    var tint: Color = Palette.bone

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Palette.display(12, .medium))
            .foregroundStyle(configuration.isPressed ? tint.opacity(0.75) : tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isPressed ? Palette.hullLift : Palette.hull)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Palette.rim, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.66), value: configuration.isPressed)
    }
}

/// The one loud button on screen. Used at most once per view.
struct SignalButtonStyle: ButtonStyle {
    var isEnabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Palette.display(12, .semibold))
            .foregroundStyle(Palette.signalInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Palette.signal.opacity(isEnabled ? 1 : 0.28))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.07 : 0)
            .animation(.spring(response: 0.24, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

/// A keycap, drawn rather than typed so glyphs line up at any size.
struct KeyCap: View {
    let text: String
    var compact = false

    var body: some View {
        Text(text)
            .font(Palette.mono(compact ? 10 : 10.5, .medium))
            .foregroundStyle(Palette.boneDim)
            .padding(.horizontal, compact ? 5 : 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Palette.bone.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Palette.rim, lineWidth: 1)
            )
    }
}
