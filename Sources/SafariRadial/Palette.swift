import AppKit
import SwiftUI

/// The app's design language.
///
/// One idea drives it: this is a **dial**, not a list of links. So the palette is
/// instrument-like — deep petrol glass, warm bone lettering, and a single hot orange used
/// only for the thing you are aiming at. Orange is the only saturated colour in the product;
/// every other surface is a shade of the same cold green-black, which is what makes the
/// signal read.
enum Palette {

    // MARK: - Surfaces

    /// Window background. Slightly green-black, never neutral grey.
    static let void = Color(red: 0.024, green: 0.078, blue: 0.090)
    static let voidRaised = Color(red: 0.039, green: 0.114, blue: 0.129)
    /// Panels, fields, rows.
    static let hull = Color(red: 0.043, green: 0.129, blue: 0.149)
    static let hullLift = Color(red: 0.063, green: 0.180, blue: 0.200)
    /// Title bar gradient ends.
    static let chromeTop = Color(red: 0.047, green: 0.141, blue: 0.161)
    static let chromeBottom = Color(red: 0.035, green: 0.114, blue: 0.129)

    // MARK: - Lines

    static let rim = Color(red: 0.949, green: 0.918, blue: 0.863).opacity(0.09)
    static let rimStrong = Color(red: 0.949, green: 0.918, blue: 0.863).opacity(0.22)

    // MARK: - Ink

    /// Warm bone rather than pure white: white on green-black looks dead and blue-shifted.
    static let bone = Color(red: 0.949, green: 0.918, blue: 0.863)
    static let boneDim = bone.opacity(0.56)
    static let boneFaint = bone.opacity(0.30)
    /// Field hints. Brighter than `boneFaint`: a placeholder has to be legible on its own.
    /// Placeholder text inside the outlined add-bar fields. At 0.42 it disappeared into the
    /// hull fill — the boxes looked empty, so nobody could tell what they were for.
    static let hint = bone.opacity(0.56)

    // MARK: - Signal

    /// The one differentiating colour. Hover, aim, primary action.
    static let signal = Color(red: 1.0, green: 0.420, blue: 0.173)
    static let signalInk = Color(red: 0.125, green: 0.051, blue: 0.016)
    /// Confirmed / success. Deliberately close to the teal base, not a second accent.
    static let mint = Color(red: 0.435, green: 0.847, blue: 0.745)
    static let alarm = Color(red: 1.0, green: 0.361, blue: 0.478)

    // MARK: - Type

    /// Avenir Next ships on every Mac and is not the default UI face, which is exactly why
    /// the product does not look like a stock window. SF Pro is the fallback.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .custom("Avenir Next", size: size).weight(weight)
    }

    /// Everything numeric or technical: slot numbers, keycaps, URLs, counts.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // AppKit mirrors, for the canvas-drawn radial.
    static func nsDisplay(_ size: CGFloat, _ weight: NSFont.Weight = .semibold) -> NSFont {
        let name: String
        switch weight {
        case .regular, .light, .thin, .ultraLight: name = "AvenirNext-Regular"
        case .medium: name = "AvenirNext-Medium"
        case .bold, .heavy, .black: name = "AvenirNext-Bold"
        default: name = "AvenirNext-DemiBold"
        }
        return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func nsMono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    // AppKit colour for the radial renderer and the recorder.
    static let nsSignal = NSColor(calibratedRed: 1.0, green: 0.420, blue: 0.173, alpha: 1)
    static let nsVoid = NSColor(calibratedRed: 0.024, green: 0.078, blue: 0.090, alpha: 1)
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
