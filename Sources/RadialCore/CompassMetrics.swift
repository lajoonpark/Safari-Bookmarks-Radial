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
    ///
    /// Pushed out from 0.575: a wedge is wider the further it is from the hub, and the extra
    /// room is what lets every name print at one size instead of shrinking to fit.
    public var labelRadius: CGFloat { cardRadius * 0.630 }

    /// The one size every wedge name is printed at.
    ///
    /// A single value per page, never per label. Names used to shrink independently until they
    /// fitted their wedge, so one long bookmark ("Artificial Analysis") ended up at half the
    /// size of its neighbours and the dial read as uneven. Long names now wrap onto a second
    /// line at this same size instead. Nine wedges are narrower than eight, hence the step.
    public func labelFontSize(sliceCount: Int) -> CGFloat {
        let share: CGFloat = sliceCount > 8 ? 0.066 : 0.072
        return max(CompassMetrics.minimumLabelSize, cardRadius * share)
    }

    /// Smallest a wedge name is ever printed. Above the proportional share at small cards,
    /// which is deliberate: legible beats proportional. Not higher, because at the 110pt
    /// minimum card a bigger floor leaves wedges too narrow and names truncate hard.
    public static let minimumLabelSize: CGFloat = 10

    /// Breathing room between a name and its wedge walls. Scales with the card, because a fixed
    /// 7pt eats a third of a small card's wedge.
    public var labelPad: CGFloat { min(7, cardRadius * 0.035) }

    /// Slot numerals, printed in gates cut through the degree scale.
    public var numeralFontSize: CGFloat { max(9, cardRadius * 0.072) }

    // MARK: Furniture

    public var lugWidth: CGFloat { cardRadius * 0.070 }
    public var lugStemTop: CGFloat { caseRadius - cardRadius * 0.055 }
    public var lugStemBottom: CGFloat { caseRadius + cardRadius * 0.070 }
    public var lugBowRadius: CGFloat { cardRadius * 0.062 }
    public var lugBowCenter: CGFloat { caseRadius + cardRadius * 0.128 }

    public var hingeHalfSpan: CGFloat { cardRadius * 0.135 }

    // MARK: Lid

    /// Outer radius of the lid.
    ///
    /// Slightly inside the case's rim, because a lid closes into the case's raised lip the way a real
    /// pocket compass does, and the brass lip is what you see around it when it is shut. It is
    /// also the lid's own pivot: `CompassLid` keeps the hinge tangent to this rim, so a lid
    /// smaller than the case still hangs from the case's back edge with no gap opening up.
    ///
    /// 0.95 rather than 1: the open lid stands toward the camera, and perspective magnifies it by
    /// about 17% at the open angle, so a lid that is flush with the case when shut is drawn wider
    /// than the case when open, which is the "second dial" look. Pulling it in by 5% cancels that
    /// without leaving a visible step at the lip. Below `cardRadius / caseRadius` (0.851) the lid
    /// could not cover the card, so there is room but not a lot; `testTheShutLidCoversTheCard`
    /// holds the floor.
    public var lidRadius: CGFloat { caseRadius * 0.95 }

    /// How deep the dish is. A lid is a shallow pan, not a plate: this is the wall you see when it
    /// is edge-on, and what makes it read as an object with a rim instead of a disc.
    public var lidDepth: CGFloat { cardRadius * 0.105 }
    /// Thickness of the wall, seen as the rim ring when the lid is open.
    public var lidWall: CGFloat { cardRadius * 0.045 }
    /// Thickness of the plate that closes the pan.
    public var lidPlate: CGFloat { cardRadius * 0.018 }
    /// The shoulder where the cover rolls over into the wall, as both a height and an inset.
    public var lidChamfer: CGFloat { cardRadius * 0.040 }

    /// Radius of the engraved plate inside the lid.
    public var lidFloorRadius: CGFloat { lidRadius - lidWall }
    /// Height of that plate above the rim plane.
    public var lidFloorHeight: CGFloat { lidDepth - lidPlate }
    /// Radius of the flat outside cover, inside the shoulder.
    public var lidCoverRadius: CGFloat { lidRadius - lidChamfer }
    /// Height at which the straight wall ends and the shoulder begins.
    public var lidShoulderHeight: CGFloat { lidDepth - lidChamfer }

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
        lidExtents(at: angle).reach
    }

    /// Distance from the centre to the side of the open lid, which is wider than the case.
    ///
    /// The open lid stands toward the camera, so perspective magnifies it: it is drawn about a
    /// quarter wider than the case it hangs from. A window that fitted only the case clipped the
    /// lid at its edge, so anything that needs the instrument's true width asks for this.
    public func lidHalfWidth(at angle: CGFloat = CompassMetrics.lidOpenAngle) -> CGFloat {
        lidExtents(at: angle).halfWidth
    }

    private func lidExtents(at angle: CGFloat) -> (reach: CGFloat, halfWidth: CGFloat) {
        let camera = CompassCamera(eyeDistance: cardRadius * RadialTilt.eyeDistanceRatio)
        let lid = CompassLid(metrics: self, openness: angle / CompassMetrics.lidOpenAngle)
        var reach: CGFloat = 0
        var halfWidth: CGFloat = 0
        // The pan has depth, so the highest point is on the cover's edge or the wall's top, not
        // the rim: sample all three rings.
        let rings: [(radius: CGFloat, height: CGFloat)] = [
            (lidRadius, 0),
            (lidRadius, lidShoulderHeight),
            (lidCoverRadius, lidDepth),
        ]
        for step in 0...48 {
            let a = CGFloat(step) / 48 * 2 * .pi
            for ring in rings {
                let point = camera.project(lid.swing(lid.point(radius: ring.radius, angle: a, height: ring.height))).point
                reach = max(reach, -point.y)
                halfWidth = max(halfWidth, abs(point.x))
            }
        }
        return (reach, halfWidth)
    }

    /// Total height the instrument needs, lid open.
    public var openHeight: CGFloat { lidReach() + lugReach }

    /// Shrinks the card until the whole instrument fits `available` points of height.
    ///
    /// The user's radius setting is an upper bound, not a promise: an open compass is about 4.4
    /// card-radii tall, so the largest setting would run off the bottom of a laptop screen. (It was
    /// 3.4 until the lid was enlarged to show its face, and 4 before the lid became a pan with a
    /// depth of its own; the taller lid moved the top of the instrument up, and this is what keeps
    /// it on screen.)
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
