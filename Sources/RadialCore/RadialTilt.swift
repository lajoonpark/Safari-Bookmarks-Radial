import Foundation
// Required, not incidental: this module is built with default cross-module optimization, so its
// optimized SIL is serialized and linked into the AppKit target. Importing only Foundation gives
// `CGPoint` the ClangImporter's Double-field view, while AppKit sees the CoreGraphics overlay's
// CGFloat fields; the SIL linker then deserializes point arithmetic whose field types do not
// match the consumer's and the compiler crashes (swiftlang/swift#92222). Loading the overlay
// here makes both modules agree. Guarded because CoreGraphics does not exist outside Darwin.
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A slight 3D tilt of the dial's plane, as a planar perspective projection.
///
/// The dial is treated as a disc lying flat in the screen plane. Tilting it and viewing it
/// from `eyeDistance` points away produces a homography: points nearer the viewer grow,
/// points further away shrink. That asymmetry is the whole effect — an orthographic version
/// of the same rotation is just a squash, which reads as a flat ellipse rather than as a
/// surface leaning under the cursor.
///
/// Lives here (not in the renderer) because the inverse matters: the pointer arrives in
/// untilted screen coordinates, so hover and click have to be mapped back through the same
/// projection before they can be hit tested. Getting that wrong makes the dial fire the
/// wrong slice, which is the one thing this app cannot afford.
public struct RadialTilt: Equatable, Sendable {
    /// Rotation about the horizontal axis, radians. Positive tips the top of the disc away.
    public var pitch: CGFloat
    /// Rotation about the vertical axis, radians. Positive tips the right edge away.
    public var roll: CGFloat
    /// Distance from the viewer to the dial's plane, in points. Smaller is more dramatic.
    public var eyeDistance: CGFloat

    public init(pitch: CGFloat = 0, roll: CGFloat = 0, eyeDistance: CGFloat = 800) {
        self.pitch = pitch
        self.roll = roll
        self.eyeDistance = max(1, eyeDistance)
    }

    /// Largest tilt the menu allows.
    ///
    /// Calibrated rather than guessed. At 6° with a 1400pt eye the near and far edges differ
    /// by only 4% in size, which nobody can see — the dial just looked slightly off-centre.
    /// 11° at 4× the radius gives roughly 10% asymmetry and a 2% squash: visible as a lean,
    /// still obviously a ring. Past ~15° the far wedges start to foreshorten into slivers and
    /// the slot numbers drift off their ticks.
    public static let maxAngle: CGFloat = 11 * .pi / 180

    /// Eye distance as a multiple of the dial's radius. Fixed ratio, so the amount of
    /// perspective is the same at every menu size instead of growing with it.
    public static let eyeDistanceRatio: CGFloat = 4

    /// No tilt at all. Used as the resting state and as the identity case.
    public static let flat = RadialTilt()

    /// Tilt that leans the disc *toward* `point` (untilted ring space, y down).
    ///
    /// The part of the disc under the pointer swings closer to the viewer, which is what
    /// makes the dial feel like it is turning to face you rather than sliding sideways.
    /// `radius` is the dial's own radius, used both to ease the lean in and to scale the eye
    /// distance, so a 140pt dial and a 320pt dial lean by the same *apparent* amount.
    public init(leaningToward point: CGPoint, radius: CGFloat, eyeDistance: CGFloat? = nil) {
        self.init(eyeDistance: eyeDistance ?? max(1, radius * RadialTilt.eyeDistanceRatio))
        let distance = (point.x * point.x + point.y * point.y).squareRoot()
        guard radius > 0, distance > 0 else { return }
        // Eased in from the hub, so the disc does not snap to full angle the moment the
        // pointer leaves the centre.
        let strength = RadialTilt.maxAngle * Self.smoothstep(distance / radius)
        let ux = point.x / distance
        let uy = point.y / distance
        // Depth of a point is `-roll·x + pitch·y` (small-angle): the pointer's own side of
        // the disc must come out positive, i.e. toward the viewer.
        roll = -strength * ux
        pitch = strength * uy
    }

    public var isFlat: Bool { abs(pitch) < 1e-6 && abs(roll) < 1e-6 }

    private static func smoothstep(_ t: CGFloat) -> CGFloat {
        let x = min(1, max(0, t))
        return x * x * (3 - 2 * x)
    }

    /// The rotation as a linear map plus a depth row, before the perspective divide.
    private var coefficients: (xx: CGFloat, yx: CGFloat, yy: CGFloat, zx: CGFloat, zy: CGFloat) {
        let sr = sin(roll), cr = cos(roll), sp = sin(pitch), cp = cos(pitch)
        return (xx: cr, yx: sr * sp, yy: cp, zx: -sr * cp, zy: sp)
    }

    /// Maps an untilted point (relative to the dial centre, y down) to its tilted position.
    public func project(_ point: CGPoint) -> CGPoint {
        guard !isFlat else { return point }
        let k = coefficients
        let depth = k.zx * point.x + k.zy * point.y
        let scale = eyeDistance / (eyeDistance - depth)
        return CGPoint(x: k.xx * point.x * scale, y: (k.yx * point.x + k.yy * point.y) * scale)
    }

    /// Inverse of `project`: where a tilted point came from.
    ///
    /// Solved directly rather than iterated. Fixing the projected point turns the
    /// perspective divide into a 2×2 linear system in the original coordinates.
    public func unproject(_ point: CGPoint) -> CGPoint {
        guard !isFlat else { return point }
        let k = coefficients
        let d = eyeDistance
        let a11 = d * k.xx + point.x * k.zx
        let a12 = point.x * k.zy
        let a21 = d * k.yx + point.y * k.zx
        let a22 = d * k.yy + point.y * k.zy
        let determinant = a11 * a22 - a12 * a21
        guard abs(determinant) > 1e-9 else { return point }
        let r1 = d * point.x
        let r2 = d * point.y
        return CGPoint(
            x: (r1 * a22 - a12 * r2) / determinant,
            y: (a11 * r2 - r1 * a21) / determinant
        )
    }

    /// The affine part of the projection at a point, for placing text along the tilt.
    public func scale(at point: CGPoint) -> CGFloat {
        guard !isFlat else { return 1 }
        let k = coefficients
        return eyeDistance / (eyeDistance - (k.zx * point.x + k.zy * point.y))
    }
}
