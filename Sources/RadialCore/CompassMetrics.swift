import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A point in the instrument's own 3D space.
///
/// Card space: `x` right, `y` **down** (to match the flipped view coordinates the dial has
/// always used), `z` toward the viewer. The compass is a flat disc lying at `z = 0`, its case
/// wall drops to negative `z`, and the lid swings up out of the plane about the top rim.
public struct Point3D: Equatable, Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public var z: CGFloat

    public init(x: CGFloat, y: CGFloat, z: CGFloat = 0) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// A point on the dial's plane, from polar coordinates measured clockwise from 12 o'clock.
    public init(radius: CGFloat, angle: CGFloat, z: CGFloat = 0) {
        self.init(x: radius * sin(angle), y: -radius * cos(angle), z: z)
    }

    public static let zero = Point3D(x: 0, y: 0, z: 0)
}

/// The compass's proportions, all as multiples of the printed card's radius.
///
/// One number — the card radius — drives every other dimension, so the instrument scales as
/// a single object instead of drifting apart at different menu sizes. These are the ratios the
/// design harness settled on; they are not arbitrary, and the comments say why where it
/// matters.
public struct CompassMetrics: Equatable, Sendable {
    public let cardRadius: CGFloat

    public init(cardRadius: CGFloat) {
        self.cardRadius = max(1, cardRadius)
    }

    // MARK: Bands

    /// Outer edge of the brass case.
    public var caseRadius: CGFloat { cardRadius * 1.175 }
    /// How far the case wall drops below the card.
    public var wallDepth: CGFloat { cardRadius * 0.085 }
    /// How far the card sits below the bezel's crest.
    public var cardDepth: CGFloat { cardRadius * 0.020 }
    /// Brass boss at the centre.
    public var hubRadius: CGFloat { cardRadius * 0.185 }
    /// The window in the boss that reads back the aimed slot.
    public var hubWindowRadius: CGFloat { hubRadius * 0.56 }
    public var hubPinRadius: CGFloat { cardRadius * 0.018 }

    /// Where the painted sectors start and stop.
    public var sectorInset: CGFloat { cardRadius * 0.250 }
    public var sectorOutset: CGFloat { cardRadius * 0.880 }

    /// Printed degree scale, on the card's outer margin.
    public var scaleInset: CGFloat { cardRadius * 0.895 }
    public var scaleOutset: CGFloat { cardRadius * 0.985 }
    /// The slot numerals sit in gates cut through the scale at each bearing.
    public var numeralRadius: CGFloat { cardRadius * 0.930 }
    /// Radius of a wedge's name.
    public var labelRadius: CGFloat { cardRadius * 0.575 }

    // MARK: Furniture

    public var lugWidth: CGFloat { cardRadius * 0.070 }
    public var lugStemTop: CGFloat { caseRadius - cardRadius * 0.055 }
    public var lugStemBottom: CGFloat { caseRadius + cardRadius * 0.070 }
    public var lugBowRadius: CGFloat { cardRadius * 0.062 }
    public var lugBowCenter: CGFloat { caseRadius + cardRadius * 0.128 }

    public var hingeHalfSpan: CGFloat { cardRadius * 0.135 }

    // MARK: Lid

    /// How far the lid swings open.
    ///
    /// Chosen by eye against a rendered harness, not derived. At 90° the lid stands edge-on to
    /// a camera looking down at the dial and reads as a sliver; past ~120° it leans back over
    /// the top of the case and crowds the screen edge. 112° keeps the lid's inside face legible
    /// and still reads unambiguously as "open".
    public static let lidOpenAngle: CGFloat = 112 * .pi / 180

    // MARK: Extent

    /// Distance from the centre to the furthest point of the case, before the lid.
    public var caseReach: CGFloat { caseRadius }

    /// Distance from the centre down to the bottom of the lanyard bow.
    public var lugReach: CGFloat { lugBowCenter + lugBowRadius * 1.18 }

    /// Distance from the centre up to the lid's far edge when fully open.
    ///
    /// The lid is the same disc as the case, hinged on its own top rim, so its far edge sits a
    /// full diameter from the hinge. That is why an open compass is much taller than it is
    /// wide, and why the dial cannot simply be centred on the pointer.
    public func lidReach(at angle: CGFloat = CompassMetrics.lidOpenAngle) -> CGFloat {
        let hingeY = -cardRadius * 1.175
        let farEdge = 2 * cardRadius * 1.175
        return abs(hingeY + farEdge * cos(angle))
    }

    /// Total height the instrument needs, lid open.
    public var openHeight: CGFloat { lidReach() + lugReach }

    /// Shrinks the card until the whole instrument fits `available` points of height.
    ///
    /// The user's radius setting is an upper bound, not a promise: an open compass is roughly
    /// 3.4 card-radii tall, so the largest setting would run off the bottom of a laptop screen.
    /// The floor keeps the dial usable rather than elegant, because below about 110pt the slot
    /// numerals stop being legible and the keyboard mapping becomes guesswork.
    public func fitted(toHeight available: CGFloat) -> CompassMetrics {
        guard available > 0 else { return self }
        let needed = openHeight
        guard needed > available else { return self }
        let minimum = CompassMetrics(cardRadius: 110)
        let scaled = CompassMetrics(cardRadius: cardRadius * available / needed)
        return scaled.cardRadius < minimum.cardRadius ? minimum : scaled
    }
}
