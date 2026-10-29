import AppKit
import Foundation

/// The instrument's wear, as deterministic data.
///
/// Every blotch, scuff and age spot on the compass is generated from a fixed seed, so the same
/// object appears every time the menu opens. That matters more than it sounds: random wear
/// re-rolled per frame would crawl, and re-rolled per open would make the compass a different
/// object each time — which reads as a rendering artefact rather than as a worn tool.
///
/// Values are in card-radius units, so the wear scales with the instrument and a 140pt dial
/// wears exactly like a 320pt one.
final class CompassGrain {

    struct Blot { let x: CGFloat; let y: CGFloat; let radius: CGFloat; let alpha: CGFloat }
    struct Buff { let angle: CGFloat; let radius: CGFloat; let length: CGFloat; let alpha: CGFloat }

    private let patinaBlots: [Blot]
    private let buffs: [Buff]
    private let spots: [Blot]
    private let tile: NSImage

    /// Enough of a tile that the repeat does not read as a grid, small enough to build once.
    private static let tileSize = 96

    init(seed: UInt64 = 20_261_029) {
        var random = SplitMix64(seed: seed)

        // Patina: along the outer third, where a hand brushes and sweat sits.
        patinaBlots = (0..<30).map { _ in
            let angle = random.unit() * 2 * .pi
            let radius = 0.94 + random.unit() * 0.20
            return Blot(
                x: radius * sin(angle),
                y: -radius * cos(angle),
                radius: 0.10 + random.unit() * 0.20,
                alpha: 0.05 + random.unit() * 0.10
            )
        }

        // Burnished arcs: the high points a thumb keeps wiping clean.
        buffs = (0..<11).map { _ in
            Buff(
                angle: random.unit() * 2 * .pi,
                radius: 1.02 + random.unit() * 0.10,
                length: 0.25 + random.unit() * 0.55,
                alpha: 0.06 + random.unit() * 0.10
            )
        }

        // Foxing on the paper: small, brown, faint.
        spots = (0..<26).map { _ in
            Blot(
                x: (random.unit() - 0.5) * 1.5,
                y: (random.unit() - 0.5) * 1.5,
                radius: 0.010 + random.unit() * 0.045,
                alpha: 0.05 + random.unit() * 0.10
            )
        }

        tile = CompassGrain.makeTile(size: CompassGrain.tileSize, seed: &random)
    }

    func patina(radius: CGFloat) -> [Blot] { patinaBlots }
    func buffs(radius: CGFloat) -> [Buff] { self.buffs }
    func ageSpots(radius: CGFloat) -> [Blot] { spots }

    /// Fibre grain, tiled. A single noise fill under an affine transform: full per-pixel grain
    /// through the perspective divide would cost more than the whole rest of the frame and is
    /// invisible at this scale.
    func fill(in context: CGContext, scale: CGFloat) {
        context.saveGState()
        context.setFillColor(NSColor(patternImage: tile).cgColor)
        let extent = scale * 1.4
        context.fill(CGRect(x: -extent, y: -extent, width: extent * 2, height: extent * 2))
        context.restoreGState()
    }

    private static func makeTile(size: Int, seed: inout SplitMix64) -> NSImage {
        let image = NSImage(size: NSSize(width: CGFloat(size), height: CGFloat(size)))
        image.lockFocus()
        defer { image.unlockFocus() }
        guard let context = NSGraphicsContext.current?.cgContext else { return image }
        for _ in 0..<(size * size / 3) {
            let x = CGFloat(seed.unit()) * CGFloat(size)
            let y = CGFloat(seed.unit()) * CGFloat(size)
            let value = 0.5 + (seed.unit() - 0.5) * 0.26
            let warm = seed.unit() < 0.5
            context.setFillColor(
                NSColor(
                    calibratedWhite: value,
                    alpha: warm ? 0.10 : 0.07
                ).cgColor
            )
            context.fill(CGRect(x: x, y: y, width: 1.2, height: 1.2))
        }
        return image
    }
}

/// A small deterministic generator.
///
/// `SystemRandomNumberGenerator` would be the obvious choice and is the wrong one here: this
/// data has to be identical across launches, and stable across Swift versions for the tests
/// around it to mean anything. SplitMix64 is three lines and exact.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in `[0, 1)`.
    mutating func unit() -> CGFloat {
        CGFloat(next() >> 11) / CGFloat(1 << 53)
    }
}
