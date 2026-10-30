import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The camera that makes the compass a solid object rather than a drawing.
///
/// `RadialTilt` already models a leaning disc as a homography, which is exact for anything on
/// the card's plane. The compass needs more than that: the case has depth, and the lid swings
/// on a hinge out of the plane entirely. So this extends the same rotation to three dimensions
/// and keeps `RadialTilt`'s conventions, which means at `z = 0` it agrees *exactly* with the
/// existing projection and the existing inverse still recovers the pointer.
///
/// The rotation is applied as roll (about y) then pitch (about x), matching `RadialTilt`'s
/// coefficient order so a dial that has always leaned the right way still does.
public struct CompassCamera: Equatable, Sendable {
    public var pitch: CGFloat
    public var roll: CGFloat
    public var eyeDistance: CGFloat

    public init(pitch: CGFloat = 0, roll: CGFloat = 0, eyeDistance: CGFloat = 800) {
        self.pitch = pitch
        self.roll = roll
        self.eyeDistance = max(1, eyeDistance)
    }

    public static let level = CompassCamera()

    public var isLevel: Bool { abs(pitch) < 1e-9 && abs(roll) < 1e-9 }

    /// Built from the dial's existing tilt, so the compass and the pointer maths agree.
    public init(tilt: RadialTilt) {
        self.init(pitch: tilt.pitch, roll: tilt.roll, eyeDistance: tilt.eyeDistance)
    }

    private var sinRoll: CGFloat { sin(roll) }
    private var cosRoll: CGFloat { cos(roll) }
    private var sinPitch: CGFloat { sin(pitch) }
    private var cosPitch: CGFloat { cos(pitch) }

    /// Rotates a card-space point into the viewer's frame, before the perspective divide.
    public func rotate(_ point: Point3D) -> Point3D {
        let x = point.x * cosRoll + point.z * sinRoll
        let z = -point.x * sinRoll + point.z * cosRoll
        let y = point.y * cosPitch - z * sinPitch
        let depth = point.y * sinPitch + z * cosPitch
        return Point3D(x: x, y: y, z: depth)
    }

    /// Projects a card-space point to screen space, relative to the instrument's centre.
    ///
    /// `depthScale` is the perspective divisor; text and line widths use it so they shrink on
    /// the far side of the dial instead of staying a constant size.
    public func project(_ point: Point3D) -> (point: CGPoint, depthScale: CGFloat) {
        let rotated = rotate(point)
        let scale = eyeDistance / (eyeDistance - rotated.z)
        return (CGPoint(x: rotated.x * scale, y: rotated.y * scale), scale)
    }

    public func project(x: CGFloat, y: CGFloat, z: CGFloat = 0) -> CGPoint {
        project(Point3D(x: x, y: y, z: z)).point
    }

    /// Where a projected point came from on the card's plane.
    ///
    /// The pointer arrives in screen space and the dial is drawn leaning, so hit testing has to
    /// undo the projection first. Delegating to `RadialTilt` guarantees the dial can never
    /// disagree with the hit test: both are the same algebra, which is the one thing this app
    /// cannot afford to get wrong.
    public func unprojectToCard(_ point: CGPoint) -> CGPoint {
        RadialTilt(pitch: pitch, roll: roll, eyeDistance: eyeDistance).unproject(point)
    }

    /// The depth scale at a card-space point, for sizing ink that sits on the card.
    public func depthScale(at point: Point3D) -> CGFloat {
        project(point).depthScale
    }

    /// A map from card space to screen space, for projecting whole paths at once.
    public func projector() -> (Point3D) -> CGPoint {
        { self.project($0).point }
    }
}

/// The lid, on its hinge.
///
/// A shallow brass pan pivoting on a line across its own back rim. Keeping the hinge tangent to the
/// lid's rim is not cosmetic: if the pivot were anywhere but on the disc's edge, points on the
/// hinge line would move as the lid opened and it would visibly detach and float. With the
/// hinge exactly on the rim, `hingeY` is a fixed point of the rotation at every angle.
///
/// The lid is authored shut, in its own frame: `x` and `y` as card space, and height measured
/// up from its rim plane, which rests on the case's crest. Everything on it is built that way
/// and then swung about the hinge, so the pan, its wall, its cover and its engraving cannot
/// come apart.
///
/// The disc is slightly smaller than the case (`CompassMetrics.lidRadius`) because a real lid
/// closes inside the case's lip. That is why the hinge sits at `-lidRadius` and not at the
/// case's rim: the pivot follows the lid, not the box it closes into.
public struct CompassLid: Equatable, Sendable {
    public let metrics: CompassMetrics
    /// 0 = shut, 1 = fully open.
    public var openness: CGFloat

    public init(metrics: CompassMetrics, openness: CGFloat = 0) {
        self.metrics = metrics
        self.openness = max(0, min(1, openness))
    }

    public var angle: CGFloat { openness * CompassMetrics.lidOpenAngle }

    /// The hinge line: the lid's own back rim, on the case's crest.
    ///
    /// Exactly on the rim, so the lid cannot detach as it swings. A short strap was tried here
    /// to lift the plate clear of the top numerals, and it is not needed: the shut lid covers the
    /// dial and the open one clears it. Raising the pivot would pull the lid's near edge up off
    /// the case it is supposed to rest on.
    public var hingeY: CGFloat { -metrics.lidRadius }
    /// The case's crest: the plane the shut lid's rim rests on, and the height of the pin.
    public var hingeZ: CGFloat { metrics.cardDepth }

    /// Swings a point from the lid's shut pose into its current pose.
    ///
    /// Everything on the lid is authored as though the compass were closed, then rotated about
    /// the hinge. The `rel` offset measures distance from the hinge, so the hinge line itself
    /// (`rel == 0`) never moves.
    public func swing(_ point: Point3D) -> Point3D {
        let rel = point.y - hingeY
        let c = cos(angle)
        let s = sin(angle)
        return Point3D(
            x: point.x,
            y: hingeY + rel * c - (point.z - hingeZ) * s,
            z: hingeZ + rel * s + (point.z - hingeZ) * c
        )
    }

    /// Turns a direction (a surface normal, say) with the lid. The same rotation as `swing`,
    /// without the hinge's offset, because a direction has no position to move.
    public func swingDirection(_ direction: Point3D) -> Point3D {
        let c = cos(angle)
        let s = sin(angle)
        return Point3D(
            x: direction.x,
            y: direction.y * c - direction.z * s,
            z: direction.y * s + direction.z * c
        )
    }

    public func project(_ point: Point3D, with camera: CompassCamera) -> CGPoint {
        camera.project(swing(point)).point
    }

    /// Outer radius of the lid.
    public var radius: CGFloat { metrics.lidRadius }

    /// A point on the lid, given polar coordinates in its own plane and a height above its rim.
    public func point(radius: CGFloat, angle: CGFloat, height: CGFloat = 0) -> Point3D {
        Point3D(radius: radius, angle: angle, z: hingeZ + height)
    }

    /// Whether the lid is far enough open to let the pointer reach the card.
    ///
    /// Until the lid has cleared the card, clicks belong to the lid rather than the menu. This
    /// is what stops a fast ⌘E followed by an immediate click from firing whatever slice
    /// happened to be under the cursor while the box was still opening.
    public var revealsCard: Bool { openness > 0.55 }
}
