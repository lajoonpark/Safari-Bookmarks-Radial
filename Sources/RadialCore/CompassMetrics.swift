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

    /// Radius of the lid disc.
    ///
    /// Smaller than the case, because a lid closes *inside* the case's raised lip — the same
    /// way a real pocket compass does. `CompassLid` keeps it tangent to the hinge line rather
    /// than centred on the card, so a smaller disc still pivots on the case's rim with no gap
    /// opening up as it swings.
    ///
    /// 0.72 and 0.80 were both tried and both look wrong in the same way, though for a
    /// geometry reason rather than an aesthetic one: `cardRadius / caseRadius` is 0.851, so a
    /// lid smaller than that cannot cover the card it is meant to shut over. Shrinking the lid
    /// to make the open instrument less top-heavy therefore makes the *closed* one physically
    /// impossible. 0.87 is the smallest lid that genuinely closes, and the "too large" look is
    /// dealt with by the open angle instead: at 120° the lid is foreshortened enough to read as
    /// a plate leaning back rather than as a second dial lying flat. Open angle is the only
    /// lever, precisely because this radius cannot come down.
    public var lidRadius: CGFloat { caseRadius * 0.87 }

    /// How far the lid swings open.
    ///
    /// Chosen by eye against a rendered harness, not derived.
    ///
    /// The lid has to lean well *past* vertical to show its face to a camera looking down at
    /// the card. At 90° it is exactly edge-on and projects to a flat sliver; at 104° — the
    /// first value tried — it was still only a fifth as tall as it was wide, so the lid read as
    /// a plate seen edge-on rather than as an opened lid.
    ///
    /// 150° made the face broad and nearly round, which is legible but is also why the lid
    /// loomed: head-on, a disc most of the case's width reads as a second dial. The angle is
    /// the right lever for that, rather than the lid's radius — the radius is pinned from below
    /// by `testTheShutLidCoversTheCard`. At 120° the same lid keeps a face two-thirds as tall
    /// as it is wide (legible) while leaning back far enough that it reads as a plate on a
    /// hinge. 138° was still too flat, and below ~112° the rose stops resolving.
    public static let lidOpenAngle: CGFloat = 120 * .pi / 180

    // MARK: Extent

    /// Distance from the centre to the furthest point of the case, before the lid.
    public var caseReach: CGFloat { caseRadius }

    /// Distance from the centre down to the bottom of the lanyard bow.
    public var lugReach: CGFloat { lugBowCenter + lugBowRadius * 1.18 }

    /// Distance from the centre up to the lid's far edge when fully open.
    ///
    /// Sampled through the projection the renderer actually uses, because the lid's far edge
    /// stands off the card's plane and the camera magnifies it. A flat calculation — what this
    /// replaced — said the open lid reached 2.06 card-radii while it was drawn at 4.5, which
    /// is why the top of the open lid used to hang off the screen and the layout reserved far
    /// less room than the instrument needed.
    public func lidReach(at angle: CGFloat = CompassMetrics.lidOpenAngle) -> CGFloat {
        let camera = CompassCamera(eyeDistance: cardRadius * RadialTilt.eyeDistanceRatio)
        let lid = CompassLid(metrics: self, openness: angle / CompassMetrics.lidOpenAngle)
        var reach: CGFloat = 0
        for step in 0...48 {
            let a = CGFloat(step) / 48 * 2 * .pi
            let point = camera.project(lid.swing(lid.point(radius: lidRadius, angle: a))).point
            reach = max(reach, -point.y)
        }
        return reach
    }

    /// Total height the instrument needs, lid open.
    public var openHeight: CGFloat { lidReach() + lugReach }

    /// Shrinks the card until the whole instrument fits `available` points of height.
    ///
    /// The user's radius setting is an upper bound, not a promise: an open compass is a little
    /// over 4 card-radii tall, so the largest setting would run off the bottom of a laptop
    /// screen. (It was 3.4 until the lid was enlarged to show its face; the taller lid moved the
    /// top of the instrument up, and this is what keeps it on screen.)
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
