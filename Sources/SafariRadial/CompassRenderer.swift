import AppKit
import Foundation
import RadialCore

/// Draws the compass.
///
/// Structure mirrors the object: a brimmed brass case with a card seated in it, the card's
/// printing, the slices, and the needle, every one of them built in flat card space and pushed
/// through `CompassCamera` on the way to the page. Nothing is drawn in screen coordinates
/// except the scrim and the hints, so the whole instrument leans as one solid thing.
///
/// The lid is a separate pass on its own hinge, because it is a separate object that happens
/// to share a pivot.
final class CompassRenderer {

    struct State {
        var metrics: CompassMetrics
        var camera: CompassCamera
        var lid: CompassLid
        var slices: [Bookmark]
        var hoveredSlice: Int?
        var hover: [CGFloat]
        var press: [CGFloat]
        var hubHover: CGFloat
        var needleAngle: CGFloat
        var showsNumbers: Bool
        /// The print and what lights it: labels, card printing, the slice wash and the sweep.
        var contentAlpha: Double
        /// The case and everything in it. Applied once, to a transparency layer around the case.
        var caseAlpha: Double
        /// The scrim behind the instrument. It sits outside that layer.
        var scrimAlpha: Double
        /// How far the box has risen, 0 to 1. The contact shadow is wider while the instrument is still
        /// coming down and tightens to its settled size as it lands.
        var presence: Double = 1
        /// How far the box is still set down, in the units this context is drawn in (the caller has
        /// already applied the set-down scale). Applied after the scrim, so the backdrop does not move.
        var dropOffset: CGFloat = 0
        var sweep: Double
        var pageAlpha: Double
    }

    private let grain = CompassGrain()

    func draw(_ state: State, in context: CGContext, at centre: CGPoint) {
        let m = state.metrics

        context.saveGState()
        context.translateBy(x: centre.x, y: centre.y)

        // The scrim is the backdrop the instrument fades into, so it stays outside the layer.
        drawScrim(in: context, state: state)
        // The set-down drop comes after the scrim, so the backdrop stays where it is while the
        // instrument lands. Everything below moves with it, the layer's bounds included.
        context.translateBy(x: 0, y: state.dropOffset)

        // The case fades as one object. Everything from the contact shadow to the lid is composited
        // into a single layer at `caseAlpha`, so no translucent pass inside it can stack on another
        // mid-fade. At rest the layer is skipped, so the settled instrument pays nothing for it.
        let layered = state.caseAlpha < 0.999
        if layered {
            context.setAlpha(CGFloat(state.caseAlpha))
            context.beginTransparencyLayer(in: instrumentBounds(state), auxiliaryInfo: nil)
        }
        drawContactShadow(in: context, state: state)
        drawLidShadow(in: context, state: state)

        // From here down everything is in card space: origin at the hub, y down, projected.
        drawCaseWall(in: context, state: state, metrics: m)
        drawLug(in: context, state: state, metrics: m)
        drawBrass(in: context, state: state, metrics: m)
        drawCard(in: context, state: state, metrics: m)
        drawCardPrinting(in: context, state: state, metrics: m)
        // After the card, not before it. The barrel and its knuckles stand proud of the card's
        // plane on the case's rim, and they overhang the card's edge by a few points; drawn
        // underneath, the card painted over the knuckles and the hinge — and the rust in it —
        // disappeared behind the dial.
        drawHinge(in: context, state: state, metrics: m)
        drawSliceWash(in: context, state: state, metrics: m)
        drawNeedle(in: context, state: state, metrics: m)
        drawSliceLabels(in: context, state: state, metrics: m)
        drawHub(in: context, state: state, metrics: m)
        drawSweep(in: context, state: state, metrics: m)
        // Last, because it is genuinely the topmost thing here: shut, it lies just above the
        // card; swinging, its lower half passes in front of the card's near edge. Drawing it
        // before the card (as this used to) let the card paint over the lid, so the lid looked
        // clipped along a straight line for the whole first half of the opening swing.
        drawLid(in: context, state: state)
        if layered {
            context.endTransparencyLayer()
        }

        context.restoreGState()
    }
}

// MARK: - Geometry helpers

extension CompassRenderer {

    /// A circle in card space, sampled densely enough that the projection shows no facets.
    func circle(_ radius: CGFloat, _ state: State, steps: Int = 96) -> [CGPoint] {
        (0...steps).map { step in
            let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
            return state.camera.project(x: radius * sin(angle), y: -radius * cos(angle))
        }
    }

    /// An annulus as two subpaths of opposite winding; fill it with `.evenOdd`.
    func annulus(outer: CGFloat, inner: CGFloat, _ state: State) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: circle(outer, state))
        path.closeSubpath()
        path.addLines(between: circle(inner, state).reversed())
        path.closeSubpath()
        return path
    }

    /// A wedge, from the dial's tested `RadialLayout` — the same geometry hit testing uses.
    func wedge(
        index: Int,
        inset: CGFloat,
        inner: CGFloat,
        outer: CGFloat,
        layout: RadialLayout,
        _ state: State
    ) -> CGPath {
        let drawn = layout.drawableRange(of: index, inset: inset)
        let path = CGMutablePath()
        let steps = max(3, Int((drawn.sweep / (.pi / 20)).rounded(.up)))
        let outerArc = (0...steps).map { step -> CGPoint in
            let angle = drawn.start + drawn.sweep * CGFloat(step) / CGFloat(steps)
            return state.camera.project(x: outer * sin(angle), y: -outer * cos(angle))
        }
        let innerArc = stride(from: steps, through: 0, by: -1).map { step -> CGPoint in
            let angle = drawn.start + drawn.sweep * CGFloat(step) / CGFloat(steps)
            return state.camera.project(x: inner * sin(angle), y: -inner * cos(angle))
        }
        path.addLines(between: outerArc + innerArc)
        path.closeSubpath()
        return path
    }

    /// Depth scale at a card-space point, bounded so type never gets silly at the far rim.
    func inkScale(at point: Point3D, _ state: State) -> CGFloat {
        min(1.06, max(0.94, state.camera.depthScale(at: point)))
    }

    func fill(_ points: [CGPoint], _ context: CGContext, _ colour: NSColor, rule: CGPathFillRule = .winding) {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(colour.cgColor)
        context.fillPath(using: rule)
    }

    func stroke(_ points: [CGPoint], _ context: CGContext, _ colour: NSColor, width: CGFloat) {
        let path = CGMutablePath()
        path.addLines(between: points)
        context.addPath(path)
        context.setStrokeColor(colour.cgColor)
        context.setLineWidth(width)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.strokePath()
    }

    func line(_ a: CGPoint, _ b: CGPoint, _ context: CGContext, _ colour: NSColor, width: CGFloat) {
        stroke([a, b], context, colour, width: width)
    }

    /// Type laid on the instrument: centred on `point`, squeezed vertically by the depth scale
    /// so it sits *on* the leaning surface rather than floating above it.
    func drawText(
        _ text: String,
        at point: CGPoint,
        scale: CGFloat,
        font: NSFont,
        colour: NSColor,
        in context: CGContext
    ) {
        let string = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: colour,
        ])
        let size = string.size()
        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        context.scaleBy(x: 1, y: max(0.5, scale))
        string.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
        context.restoreGState()
    }

    /// The page the instrument can paint on, in view space. The case layer is clipped to this, so
    /// it has to reach the lid at its highest under the current tilt, the contact shadow (drawn flat
    /// in view space, 1.5 case radii out, further while it is landing, and dropped 0.12 below the
    /// centre) and the lug.
    private func instrumentBounds(_ state: State) -> CGRect {
        let m = state.metrics
        let margin = m.cardRadius * 0.05
        let lidTop = (0...96).map { step -> CGFloat in
            let angle = CGFloat(step) / 96 * 2 * .pi
            let point = Point3D(radius: state.lid.radius, angle: angle)
            return state.camera.project(state.lid.swing(point)).point.y
        }.min() ?? 0
        let spread = contactShadowSpread(state)
        let half = m.caseRadius * 1.5 * spread
        let top = min(lidTop, -half) - margin
        let bottom = max(m.lugReach, m.caseRadius * (0.12 + 1.5 * 1.06 * spread)) + margin
        return CGRect(x: -half - margin, y: top, width: (half + margin) * 2, height: bottom - top)
    }
}

// MARK: - Scrim and shadows

extension CompassRenderer {

    private func scrimRadius(_ state: State) -> CGFloat {
        max(state.metrics.caseRadius * 2.9, 460)
    }

    private func drawScrim(in context: CGContext, state: State) {
        // Warm dark, and only under the instrument: dimming the whole screen would make this
        // a modal instead of an overlay you can still see past.
        let radius = scrimRadius(state)
        let alpha = state.scrimAlpha
        let colours = [
            CompassTheme.shadow.withAlphaComponent(CompassTheme.backdropAlpha * CGFloat(alpha)).cgColor,
            CompassTheme.shadow.withAlphaComponent(CompassTheme.backdropMidAlpha * CGFloat(alpha)).cgColor,
            CompassTheme.shadow.withAlphaComponent(0).cgColor,
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colours,
            locations: [0, 0.46, 1] as [CGFloat]
        ) else { return }
        context.drawRadialGradient(
            gradient,
            startCenter: .zero,
            startRadius: 0,
            endCenter: .zero,
            endRadius: radius,
            options: []
        )
    }

    /// How far the contact shadow reaches, relative to its settled size: 1.15 at presence 0 (the box
    /// not yet risen), easing to 1 as the instrument lands. Written as `1 + k * (1 - p)` so the rest
    /// value is exactly 1.
    private func contactShadowSpread(_ state: State) -> CGFloat {
        CGFloat(1 + 0.15 * (1 - state.presence))
    }

    private func drawContactShadow(in context: CGContext, state: State) {
        let m = state.metrics
        let radius = m.caseRadius * 1.5 * contactShadowSpread(state)
        let centre = CGPoint(x: 0, y: m.caseRadius * 0.12)
        let colours = [
            NSColor.black.withAlphaComponent(0.62).cgColor,
            NSColor.black.withAlphaComponent(0.30).cgColor,
            NSColor.black.withAlphaComponent(0).cgColor,
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colours,
            locations: [0, 0.62, 1] as [CGFloat]
        ) else { return }
        context.saveGState()
        context.translateBy(x: centre.x, y: centre.y)
        context.scaleBy(x: 0.95, y: 1.06)
        context.drawRadialGradient(
            gradient,
            startCenter: .zero,
            startRadius: m.caseRadius * 0.5,
            endCenter: .zero,
            endRadius: radius,
            options: []
        )
        context.restoreGState()
    }

    /// The lid's shadow on the case top.
    ///
    /// Clipped to the case and kept shallow. A free-floating ellipse straddling the hinge is
    /// what made the lid read as detached: it drew a dark band in the air between lid and box,
    /// which the eye takes as a gap. Painted inside the brass instead, it lands on the object.
    private func drawLidShadow(in context: CGContext, state: State) {
        let angle = state.lid.angle
        guard sin(angle) > 0.12 else { return }
        let m = state.metrics
        let near = min(1, max(0, (CGFloat(sin(angle)) - 0.12) / 0.6))
        let radius = m.lidRadius

        context.saveGState()
        let silhouette = (0...96).map { step -> CGPoint in
            let angle = CGFloat(step) / 96 * 2 * .pi
            return state.camera.project(
                x: m.caseRadius * sin(angle), y: -m.caseRadius * cos(angle), z: m.cardDepth
            )
        }
        let clip = CGMutablePath()
        clip.addLines(between: silhouette)
        clip.closeSubpath()
        context.addPath(clip)
        context.clip()

        let hinge = state.camera.project(Point3D(x: 0, y: state.lid.hingeY, z: 0)).point
        let top = hinge.y - radius * 0.02
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor(calibratedRed: 0.094, green: 0.063, blue: 0.031, alpha: 1)
                    .withAlphaComponent(0.30 * near).cgColor,
                NSColor(calibratedRed: 0.094, green: 0.063, blue: 0.031, alpha: 1)
                    .withAlphaComponent(0.13 * near).cgColor,
                NSColor(calibratedRed: 0.094, green: 0.063, blue: 0.031, alpha: 1)
                    .withAlphaComponent(0).cgColor,
            ] as CFArray,
            locations: [0, 0.45, 1] as [CGFloat]
        ) {
            context.saveGState()
            context.clip(to: CGRect(x: -m.caseRadius, y: top,
                                    width: m.caseRadius * 2, height: radius * 0.40))
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: top),
                end: CGPoint(x: 0, y: top + radius * 0.34),
                options: []
            )
            context.restoreGState()
        }
        context.restoreGState()
    }
}

// MARK: - The lid

extension CompassRenderer {

    private func drawLid(in context: CGContext, state: State) {
        let lid = state.lid
        let radius = lid.radius
        // No fade of its own. The lid is part of the case, so the case layer in `draw` fades it with
        // everything else. Shut, it stays opaque over the card until that layer takes it out.

        func lidPoint(_ angle: CGFloat, _ r: CGFloat) -> CGPoint {
            state.camera.project(lid.swing(Point3D(radius: r, angle: angle))).point
        }
        /// A point given in the lid's own plane, cartesian, origin at its boss.
        func lidFlat(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            state.camera.project(lid.swing(Point3D(x: x, y: y, z: 0))).point
        }

        let rim = (0...96).map { lidPoint(CGFloat($0) / 96 * 2 * .pi, radius) }
        let rimPath = CGMutablePath()
        rimPath.addLines(between: rim)
        rimPath.closeSubpath()

        var bounds = CGRect(origin: rim[0], size: .zero)
        for point in rim { bounds = bounds.union(CGRect(origin: point, size: .zero)) }
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)

        // The plate's milled edge, as a thin crescent beneath the face. It has to be thin and
        // warm: a thick dark band here reads as a gap between lid and case rather than as
        // metal, and makes the lid look like it is floating.
        context.saveGState()
        context.translateBy(x: 0, y: radius * 0.012 * sin(lid.angle))
        context.addPath(rimPath)
        context.setFillColor(NSColor(calibratedRed: 0.239, green: 0.184, blue: 0.110, alpha: 1).cgColor)
        context.fillPath()
        context.restoreGState()

        // Face. The lid leans away from the viewer, so its inside is a step darker than the
        // case's bright top — lit like the case it reads as a plate hovering over the brass.
        context.saveGState()
        context.addPath(rimPath)
        context.setFillColor(CompassTheme.brassMid.cgColor)
        context.fillPath()
        context.addPath(rimPath)
        context.clip()

        // Light comes from the lower left here: the plate tips *away*, so the near edge is
        // the shaded one and the far edge catches the light.
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor(calibratedRed: 0.290, green: 0.235, blue: 0.114, alpha: 1).cgColor,
                NSColor(calibratedRed: 0.431, green: 0.357, blue: 0.224, alpha: 1).cgColor,
                NSColor(calibratedRed: 0.545, green: 0.463, blue: 0.286, alpha: 1).cgColor,
                NSColor(calibratedRed: 0.490, green: 0.416, blue: 0.267, alpha: 1).cgColor,
            ] as CFArray,
            locations: [0, 0.20, 0.52, 1] as [CGFloat]
        ) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: bounds.maxX, y: bounds.maxY),
                end: CGPoint(x: bounds.minX, y: bounds.minY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        // Turned finish: alternating lit and shadowed bands, tightening toward the bead, because
        // a spun surface catches light on each ridge. Single dark rings read as a bullseye.
        let grooves = 34
        for step in 0..<grooves {
            let t = CGFloat(step) / CGFloat(grooves)
            let groove = radius * (0.26 + 0.70 * t)
            let ring = (0...60).map { lidPoint(CGFloat($0) / 60 * 2 * .pi, groove) }
            let strength = (0.05 + 0.05 * (1 - t))
            let colour: NSColor = step % 2 == 0
                ? NSColor.black.withAlphaComponent(strength)
                : NSColor(calibratedRed: 1, green: 0.965, blue: 0.871, alpha: 1)
                    .withAlphaComponent(strength)
            stroke(ring, context, colour, width: max(0.7, radius * 0.0055))
        }

        // Specular sweep across the far side, and a vignette into the bead, so the plate turns
        // over into its own edge instead of ending at a line.
        if let sheen = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor(calibratedRed: 1, green: 0.965, blue: 0.863, alpha: 1).withAlphaComponent(0.20).cgColor,
                NSColor(calibratedRed: 1, green: 0.965, blue: 0.863, alpha: 1).withAlphaComponent(0.05).cgColor,
                NSColor(calibratedRed: 0.078, green: 0.055, blue: 0.027, alpha: 1).withAlphaComponent(0.18).cgColor,
            ] as CFArray,
            locations: [0, 0.40, 1] as [CGFloat]
        ) {
            context.drawRadialGradient(
                sheen,
                startCenter: CGPoint(x: bounds.minX + bounds.width * 0.34,
                                     y: bounds.maxY - bounds.height * 0.34),
                startRadius: radius * 0.04,
                endCenter: centre,
                endRadius: max(bounds.width, bounds.height) * 0.58,
                options: []
            )
        }
        if let vignette = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor.black.withAlphaComponent(0).cgColor,
                NSColor.black.withAlphaComponent(0.10).cgColor,
                NSColor.black.withAlphaComponent(0.42).cgColor,
            ] as CFArray,
            locations: [0, 0.72, 1] as [CGFloat]
        ) {
            context.drawRadialGradient(
                vignette,
                startCenter: centre,
                startRadius: radius * 0.55,
                endCenter: centre,
                endRadius: radius * 1.02,
                options: []
            )
        }

        // Engraved double border inside the bead: a dark cut with a lit lower lip.
        for (r, colour, width) in [
            (radius * 0.855, NSColor.black.withAlphaComponent(0.30), CGFloat(1.1)),
            (radius * 0.815, NSColor.black.withAlphaComponent(0.22), CGFloat(0.9)),
            (radius * 0.800, NSColor.white.withAlphaComponent(0.13), CGFloat(0.8)),
        ] {
            let ring = (0...96).map { lidPoint(CGFloat($0) / 96 * 2 * .pi, r) }
            stroke(ring, context, colour, width: width)
        }

        drawLidRose(in: context, radius: radius, point: lidPoint, flat: lidFlat)

        // Maker's mark, struck into the plate below the rose.
        drawText(
            "SAFARI  RADIAL",
            at: lidFlat(0, radius * 0.50),
            scale: min(1.0, max(0.62, abs(cos(lid.angle)) + 0.55)),
            font: CompassTheme.serif(max(5.5, radius * 0.052), .semibold),
            colour: NSColor.black.withAlphaComponent(0.30),
            in: context
        )

        // Broad mottling first, then the sharper tarnish over it, so the lid's face carries the
        // same unevenness as the card rather than reading as a clean plate.
        for blotch in grain.lidUnevenness(radius: radius) {
            let point = lidFlat(blotch.x * radius, blotch.y * radius)
            let spread = blotch.radius * radius * 1.1
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    CompassTheme.patina.withAlphaComponent(blotch.alpha * CompassTheme.wearGain).cgColor,
                    CompassTheme.patina.withAlphaComponent(0).cgColor,
                ] as CFArray,
                locations: [0, 1]
            ) else { continue }
            context.saveGState()
            context.translateBy(x: point.x, y: point.y)
            context.drawRadialGradient(
                gradient,
                startCenter: .zero, startRadius: 0,
                endCenter: .zero, endRadius: spread,
                options: []
            )
            context.restoreGState()
        }

        // Tarnish, weighted to the outer third where a thumb never reaches.
        for blot in grain.lidPatina(radius: radius) {
            let point = lidFlat(blot.x * radius, blot.y * radius)
            drawWear(blot, at: point, unit: radius * 1.15, colour: CompassTheme.patina,
                     alpha: CompassTheme.wearGain, in: context)
        }
        // Rust, only along the hinge seam where moisture collects.
        for spot in grain.rust(radius: radius) {
            let point = lidFlat(spot.x * radius, spot.y * radius)
            drawWear(spot, at: point, unit: radius, colour: CompassTheme.rust,
                     alpha: CompassTheme.wearGain, in: context)
        }

        context.restoreGState()

        // Bead: only the far arc is outlined. A full outline crosses the case at the hinge and
        // makes the lid look detached from the box.
        let farArc = (0...64).map { lidPoint(.pi + CGFloat($0) / 64 * .pi, radius) }
        stroke(farArc, context, NSColor.black.withAlphaComponent(0.62),
               width: max(1.1, radius * 0.014))
        let lit = (0...40).map { lidPoint(.pi * 1.18 + CGFloat($0) / 40 * .pi * 0.85, radius) }
        stroke(lit, context,
               NSColor.white.withAlphaComponent(0.10 + 0.24 * abs(sin(lid.angle))),
               width: max(0.9, radius * 0.007))
    }

    /// One soft blot of wear — tarnish or rust — as a radial gradient.
    private func drawWear(
        _ blot: CompassGrain.Blot,
        at point: CGPoint,
        unit: CGFloat,
        colour: NSColor,
        alpha: CGFloat,
        in context: CGContext
    ) {
        let spread = blot.radius * unit
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                colour.withAlphaComponent(blot.alpha * alpha).cgColor,
                colour.withAlphaComponent(blot.alpha * 0.5 * alpha).cgColor,
                colour.withAlphaComponent(0).cgColor,
            ] as CFArray,
            locations: [0, 0.52, 1] as [CGFloat]
        ) else { return }
        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        context.drawRadialGradient(
            gradient,
            startCenter: .zero, startRadius: 0,
            endCenter: .zero, endRadius: spread,
            options: []
        )
        context.restoreGState()
    }

    /// The engraved compass rose on the lid's plate.
    ///
    /// An open compass shows its lid, and a lid with nothing on it reads as a blank disc no
    /// matter how well it is shaded — this is the detail that makes it an instrument. Cut
    /// rather than inked: every line is a shadow with a thin light edge under it.
    private func drawLidRose(
        in context: CGContext,
        radius: CGFloat,
        point: (CGFloat, CGFloat) -> CGPoint,
        flat: (CGFloat, CGFloat) -> CGPoint
    ) {
        let outer = radius * 0.555
        let waist = radius * 0.125

        // Degree ticks between the rose and the bead. Struck, not painted: each is a dark
        // cut with a lit edge on its far side, which is what makes them survive the shallow
        // angle the lid is seen at.
        for index in 0..<72 {
            let angle = CGFloat(index) / 72 * 2 * .pi
            let isLong = index % 9 == 0
            let inner = radius * (isLong ? 0.845 : 0.872)
            let outerR = radius * 0.905
            let a = point(angle, inner)
            let b = point(angle, outerR)
            context.saveGState()
            let tickAlpha: CGFloat = isLong ? 0.40 : 0.24
            context.setStrokeColor(NSColor.black.withAlphaComponent(tickAlpha).cgColor)
            context.setLineWidth(isLong ? 1.0 : 0.7)
            context.move(to: a)
            context.addLine(to: b)
            context.strokePath()
            context.restoreGState()
        }

        // The plate the rose is cut into sits a hair proud of the field and a touch lighter.
        // Without it the points have nothing to be raised *above* and read as a drawing on a
        // disc rather than as struck metal.
        let plateCentre = flat(0, 0)
        if let plate = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor(calibratedRed: 0.886, green: 0.808, blue: 0.651, alpha: 0.10).cgColor,
                NSColor(calibratedRed: 0.839, green: 0.753, blue: 0.588, alpha: 0.05).cgColor,
                NSColor(calibratedRed: 0.706, green: 0.612, blue: 0.439, alpha: 0).cgColor,
            ] as CFArray,
            locations: [0, 0.7, 1] as [CGFloat]
        ) {
            context.saveGState()
            let path = CGMutablePath()
            path.addLines(between: (0...96).map { point(CGFloat($0) / 96 * 2 * .pi, outer * 1.06) })
            path.closeSubpath()
            context.addPath(path)
            context.clip()
            context.drawRadialGradient(
                plate, startCenter: plateCentre, startRadius: 0,
                endCenter: plateCentre, endRadius: outer * 1.06, options: []
            )
            context.restoreGState()
        }

        // The rose itself. Four long points and four short ones, alternating.
        for index in 0..<8 {
            let angle = CGFloat(index) / 8 * 2 * .pi
            let isLong = index % 2 == 0
            let tip = isLong ? outer : outer * 0.62
            let w = isLong ? waist * 0.68 : waist * 0.62
            let lit: CGFloat = isLong ? 0.19 : 0.13
            let dark: CGFloat = isLong ? 0.39 : 0.30
            let apex = point(angle, tip)
            let left = point(angle - .pi / 2, w)
            let right = point(angle + .pi / 2, w)
            let spine = point(angle, w * 0.35)

            let star = CGMutablePath()
            star.addLines(between: [left, apex, right])
            star.closeSubpath()
            context.addPath(star)
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.46).cgColor)
            context.setLineWidth(max(0.8, tip * 0.012))
            context.strokePath()

            // Split down the spine: one half of each point catches the light and the other
            // holds shadow. Without the split the rose is a drawn star, not cut metal.
            let litFace = CGMutablePath()
            litFace.addLines(between: [spine, apex, left])
            litFace.closeSubpath()
            context.addPath(litFace)
            context.setFillColor(NSColor.white.withAlphaComponent(lit).cgColor)
            context.fillPath()

            let darkFace = CGMutablePath()
            darkFace.addLines(between: [spine, apex, right])
            darkFace.closeSubpath()
            context.addPath(darkFace)
            context.setFillColor(NSColor.black.withAlphaComponent(dark).cgColor)
            context.fillPath()
        }

        // The cut circle the points sit inside.
        for (r, colour, width) in [
            (outer * 1.045, NSColor.black.withAlphaComponent(0.34), CGFloat(max(1.0, radius * 0.012))),
            (outer * 1.020, NSColor.white.withAlphaComponent(0.14), CGFloat(max(0.8, radius * 0.008))),
        ] {
            let ring = (0...96).map { point(CGFloat($0) / 96 * 2 * .pi, r) }
            stroke(ring, context, colour, width: width)
        }

        // Central boss. Every point's spine converges at the middle, and without a struck
        // disc over the crossing the rose reads as a tangle of lines.
        let bossR = radius * 0.072
        let boss = (0...40).map { point(CGFloat($0) / 40 * 2 * .pi, bossR) }
        let centre = flat(0, 0)
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor(calibratedRed: 0.78, green: 0.67, blue: 0.45, alpha: 0.55).cgColor,
                NSColor(calibratedRed: 0.47, green: 0.38, blue: 0.22, alpha: 0.45).cgColor,
                NSColor(calibratedRed: 0.18, green: 0.13, blue: 0.07, alpha: 0.55).cgColor,
            ] as CFArray,
            locations: [0, 0.65, 1] as [CGFloat]
        ) {
            context.saveGState()
            let path = CGMutablePath()
            path.addLines(between: boss)
            path.closeSubpath()
            context.addPath(path)
            context.clip()
            context.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: centre.x - bossR * 0.3, y: centre.y + bossR * 0.3),
                startRadius: bossR * 0.1,
                endCenter: centre,
                endRadius: bossR,
                options: []
            )
            context.restoreGState()
        }
        stroke(boss, context, NSColor.black.withAlphaComponent(0.40), width: 0.9)
    }


}

// MARK: - The case

extension CompassRenderer {

    /// The side of the case: a strip from the top rim down by the wall depth. Drawn before the
    /// top face so it reads as being *under* it.
    private func drawCaseWall(in context: CGContext, state: State, metrics: CompassMetrics) {
        let radius = metrics.caseRadius
        let steps = 72
        var band: [CGPoint] = []
        for step in 0...steps {
            let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
            band.append(state.camera.project(
                x: radius * sin(angle), y: -radius * cos(angle), z: -metrics.wallDepth
            ))
        }
        for step in stride(from: steps, through: 0, by: -1) {
            let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
            band.append(state.camera.project(
                x: radius * sin(angle), y: -radius * cos(angle), z: -metrics.cardDepth
            ))
        }
        let path = CGMutablePath()
        path.addLines(between: band)
        path.closeSubpath()
        context.addPath(path)
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CompassTheme.brassDark.cgColor,
                CompassTheme.brassMid.cgColor,
                CompassTheme.brassDeep.cgColor,
            ] as CFArray,
            locations: [0, 0.4, 1]
        ) {
            context.saveGState()
            context.clip()
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: -radius, y: -radius),
                end: CGPoint(x: radius, y: radius),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
            context.restoreGState()
        }
    }

    private func drawBrass(in context: CGContext, state: State, metrics: CompassMetrics) {
        let outer = metrics.caseRadius
        let inner = metrics.cardRadius
        let ring = annulus(outer: outer, inner: inner, state)

        context.saveGState()
        context.addPath(ring)
        context.setFillColor(CompassTheme.brassLit.cgColor)
        context.fillPath(using: .evenOdd)

        // Cross-case light from the upper left, as in the reference.
        context.addPath(ring)
        context.clip(using: .evenOdd)
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CompassTheme.brassLit.cgColor,
                CompassTheme.brassMid.cgColor,
                CompassTheme.brassLit.cgColor,
                CompassTheme.brassMid.cgColor,
                CompassTheme.brassDark.cgColor,
                CompassTheme.brassDeep.cgColor,
            ] as CFArray,
            locations: [0, 0.18, 0.46, 0.70, 0.88, 1]
        ) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: -outer * 0.72, y: -outer * 0.78),
                end: CGPoint(x: outer * 0.72, y: outer * 0.78),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        grain.fill(in: context, scale: state.metrics.cardRadius)

        drawPatina(in: context, state: state, metrics: metrics)
        drawBuffMarks(in: context, state: state, metrics: metrics)
        drawTarnishBand(in: context, state: state, metrics: metrics)
        drawReeding(in: context, state: state, metrics: metrics)

        context.restoreGState()

        // Rim lines: the outer edge, the card's seat, and a lit inner lip.
        context.saveGState()
        for (radius, colour, width) in [
            (outer, NSColor.black.withAlphaComponent(0.60), CGFloat(1.2)),
            (inner, NSColor.black.withAlphaComponent(0.50), CGFloat(1.3)),
            (inner * 0.986, NSColor.white.withAlphaComponent(0.13), CGFloat(1)),
        ] {
            let path = CGMutablePath()
            path.addLines(between: circle(radius, state))
            path.closeSubpath()
            context.addPath(path)
            context.setStrokeColor(colour.cgColor)
            context.setLineWidth(width)
            context.strokePath()
        }
        context.restoreGState()
    }

    /// Age on the metal: soft olive blotches along the outer third, never rust spots.
    private func drawPatina(in context: CGContext, state: State, metrics: CompassMetrics) {
        for blot in grain.patina(radius: metrics.cardRadius) {
            let point = state.camera.project(Point3D(
                x: blot.x * metrics.cardRadius,
                y: blot.y * metrics.cardRadius,
                z: metrics.cardDepth
            ))
            let radius = blot.radius * metrics.cardRadius * point.depthScale
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    CompassTheme.patina.withAlphaComponent(blot.alpha * CompassTheme.wearGain).cgColor,
                    CompassTheme.patina.withAlphaComponent(blot.alpha * 0.55 * CompassTheme.wearGain).cgColor,
                    CompassTheme.patina.withAlphaComponent(0).cgColor,
                ] as CFArray,
                locations: [0, 0.6, 1]
            ) else { continue }
            context.saveGState()
            context.translateBy(x: point.point.x, y: point.point.y)
            context.drawRadialGradient(
                gradient,
                startCenter: .zero,
                startRadius: 0,
                endCenter: .zero,
                endRadius: radius,
                options: []
            )
            context.restoreGState()
        }
    }

    /// Burnished arcs where a thumb keeps polishing the metal bright.
    private func drawBuffMarks(in context: CGContext, state: State, metrics: CompassMetrics) {
        for buff in grain.buffs(radius: metrics.cardRadius) {
            let from = state.camera.project(Point3D(x: buff.radius * sin(buff.angle), y: -buff.radius * cos(buff.angle), z: metrics.cardDepth))
            let to = state.camera.project(Point3D(x: buff.radius * sin(buff.angle + buff.length), y: -buff.radius * cos(buff.angle + buff.length), z: metrics.cardDepth))
            context.saveGState()
            context.setStrokeColor(CompassTheme.brassHi.withAlphaComponent(buff.alpha * CompassTheme.wearGain).cgColor)
            context.setLineWidth(max(1.4, metrics.cardRadius * 0.012))
            context.setLineCap(.round)
            context.move(to: from.point)
            context.addLine(to: to.point)
            context.strokePath()
            context.restoreGState()
        }
    }

    /// The dark film that collects just inside the reeding, where a thumb never reaches.
    private func drawTarnishBand(in context: CGContext, state: State, metrics: CompassMetrics) {
        let outer = metrics.caseRadius
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CompassTheme.patina.withAlphaComponent(0).cgColor,
                CompassTheme.tarnishWarm.withAlphaComponent(0.10).cgColor,
                CompassTheme.patina.withAlphaComponent(0.22).cgColor,
                CompassTheme.patina.withAlphaComponent(0.44).cgColor,
            ] as CFArray,
            locations: [0, 0.55, 0.82, 1]
        ) else { return }
        context.saveGState()
        context.drawRadialGradient(
            gradient,
            startCenter: .zero,
            startRadius: outer * 0.86,
            endCenter: .zero,
            endRadius: outer,
            options: []
        )
        context.restoreGState()

        // Hands. The two places a pocket compass is held are the case's lower edge and the
        // thumb-grip beside the hinge, so those two arcs are worn brighter than the rest of a
        // tarnished rim. Drawn as broad, very soft crescents under the tarnish, because polish
        // is a thinning of the film, not a paint.
        for (from, to) in [(CGFloat(0.52), CGFloat(0.86)), (CGFloat(1.42), CGFloat(1.62))] {
            var arc: [CGPoint] = []
            for step in 0...40 {
                let t = from + (to - from) * CGFloat(step) / 40
                arc.append(state.camera.project(
                    x: outer * 0.975 * sin(t * .pi), y: -outer * 0.975 * cos(t * .pi), z: 0
                ))
            }
            context.saveGState()
            context.setLineCap(.round)
            context.setStrokeColor(CompassTheme.brassHi.withAlphaComponent(0.16).cgColor)
            context.setLineWidth(outer * 0.075)
            context.addLines(between: arc)
            context.strokePath()
            context.restoreGState()
        }
    }

    /// The knurled edge: alternating lit and shadowed ridges, drawn from the card's plane so
    /// they lean with everything else.
    private func drawReeding(in context: CGContext, state: State, metrics: CompassMetrics) {
        let outer = metrics.caseRadius
        let count = 190
        context.saveGState()
        for index in 0..<count {
            let angle = CGFloat(index) / CGFloat(count) * 2 * .pi
            let from = state.camera.project(Point3D(x: outer * 0.952 * sin(angle), y: -outer * 0.952 * cos(angle), z: metrics.cardDepth))
            let to = state.camera.project(Point3D(x: outer * sin(angle), y: -outer * cos(angle), z: metrics.cardDepth))
            let lit = index % 2 == 0
            context.setStrokeColor(
                (lit ? NSColor.white.withAlphaComponent(0.15) : NSColor.black.withAlphaComponent(0.22))
                    .withAlphaComponent(lit ? 0.15 : 0.22)
                    .cgColor
            )
            context.setLineWidth(1)
            context.move(to: from.point)
            context.addLine(to: to.point)
            context.strokePath()
        }
        context.restoreGState()
    }
}

// MARK: - Lug and hinge

extension CompassRenderer {

    private func drawLug(in context: CGContext, state: State, metrics: CompassMetrics) {
        let z = -metrics.wallDepth * 0.45

        // Stem.
        let width = metrics.lugWidth
        let stem = [
            state.camera.project(x: -width, y: metrics.lugStemTop, z: z),
            state.camera.project(x: width, y: metrics.lugStemTop, z: z),
            state.camera.project(x: width * 0.78, y: metrics.lugStemBottom, z: z),
            state.camera.project(x: -width * 0.78, y: metrics.lugStemBottom, z: z),
        ]
        let stemPath = CGMutablePath()
        stemPath.addLines(between: stem)
        stemPath.closeSubpath()
        context.addPath(stemPath)
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CompassTheme.brassDark.cgColor,
                CompassTheme.brassLit.cgColor,
                CompassTheme.brassMid.cgColor,
                CompassTheme.brassDeep.cgColor,
            ] as CFArray,
            locations: [0, 0.28, 0.60, 1]
        ) {
            context.saveGState()
            context.clip()
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: -width, y: 0),
                end: CGPoint(x: width, y: 0),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
            context.restoreGState()
        }
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        context.setLineWidth(1)
        context.strokePath()

        // Bow: a circle in card space, so it projects as the same ellipse as the case.
        let bowCentre = metrics.lugBowCenter
        let bowRadius = metrics.lugBowRadius
        let bow = (0...64).map { step -> CGPoint in
            let angle = CGFloat(step) / CGFloat(64) * 2 * .pi
            return state.camera.project(
                x: bowRadius * sin(angle),
                y: bowCentre - bowRadius * cos(angle),
                z: z
            )
        }
        context.saveGState()
        let bowPath = CGMutablePath()
        bowPath.addLines(between: bow)
        bowPath.closeSubpath()
        context.addPath(bowPath)
        context.setStrokeColor(CompassTheme.brassMid.cgColor)
        context.setLineWidth(metrics.cardRadius * 0.020)
        context.setLineCap(.round)
        context.strokePath()

        // A highlight along the upper left of the band, so the ring reads round.
        let highlight = (0...24).map { step -> CGPoint in
            let angle = -CGFloat.pi * 0.75 + (CGFloat.pi * 0.9) * CGFloat(step) / 24
            return state.camera.project(
                x: (bowRadius + metrics.cardRadius * 0.004) * sin(angle),
                y: bowCentre - (bowRadius + metrics.cardRadius * 0.004) * cos(angle),
                z: z
            )
        }
        stroke(highlight, context, NSColor.white.withAlphaComponent(0.40), width: 1.1)
        context.restoreGState()
    }

    /// The hinge barrel across the top of the case. It is what makes the open lid read as
    /// attached rather than floating above the box.
    private func drawHinge(in context: CGContext, state: State, metrics: CompassMetrics) {
        // On the lid's own pivot, not the case's rim. These used to be the same line, so the
        // barrel could be drawn at `-caseRadius` and look right; now that the lid closes inside
        // the lip and pivots on a short strap, drawing the barrel on the case's rim leaves it
        // floating a visible gap below the lid it is supposed to carry.
        let y = CompassLid(metrics: metrics).hingeY
        let z = -metrics.cardDepth * 0.5

        let shaftFrom = state.camera.project(Point3D(x: -metrics.hingeHalfSpan * 1.11, y: y, z: z))
        let shaftTo = state.camera.project(Point3D(x: metrics.hingeHalfSpan * 1.11, y: y, z: z))
        context.saveGState()
        context.setStrokeColor(CompassTheme.brassMid.cgColor)
        context.setLineWidth(metrics.cardRadius * 0.026)
        context.setLineCap(.round)
        context.move(to: shaftFrom.point)
        context.addLine(to: shaftTo.point)
        context.strokePath()
        context.restoreGState()

        for offset in [-metrics.hingeHalfSpan, 0, metrics.hingeHalfSpan] {
            let centre = state.camera.project(Point3D(x: offset, y: y, z: z))
            let radius = metrics.cardRadius * (offset == 0 ? 0.034 : 0.030)
            let rect = CGRect(
                x: centre.point.x - radius * 1.5 * centre.depthScale,
                y: centre.point.y - radius * centre.depthScale,
                width: radius * 3 * centre.depthScale,
                height: radius * 2 * centre.depthScale
            )
            context.saveGState()
            context.addEllipse(in: rect)
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    CompassTheme.brassHi.cgColor,
                    CompassTheme.brassMid.cgColor,
                    CompassTheme.brassDeep.cgColor,
                ] as CFArray,
                locations: [0, 0.5, 1]
            ) {
                context.clip()
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: rect.midX, y: rect.minY),
                    end: CGPoint(x: rect.midX, y: rect.maxY),
                    options: []
                )
                context.resetClip()
            }
            context.restoreGState()
            context.saveGState()
            context.addEllipse(in: rect)
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.50).cgColor)
            context.setLineWidth(0.9)
            context.strokePath()
            context.restoreGState()
        }

        // Rust. This is the one place on the instrument where it belongs: the steel pin of a
        // hundred-year-old hinge rusts into the brass around it, because that is where water
        // sits and the lacquer gives up first. Drawn after the knuckle highlights so it stains
        // them rather than being painted over by them.
        //
        // Small on purpose. At a reach of 0.215 card-radii the three blooms merged into a single
        // orange band across the top of the case, which read as a painted stripe rather than as
        // corrosion; rust wants to be a stain *on* the metal, not a wash *over* it.
        let reach = metrics.cardRadius * 0.088
        let bloom = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CompassTheme.rustBloom.withAlphaComponent(0.50).cgColor,
                CompassTheme.rust.withAlphaComponent(0.30).cgColor,
                CompassTheme.rust.withAlphaComponent(0.10).cgColor,
                CompassTheme.rust.withAlphaComponent(0).cgColor,
            ] as CFArray,
            locations: [0, 0.30, 0.62, 1]
        )
        for (offset, scale) in [(CGFloat(-1), CGFloat(1.0)), (CGFloat(0), CGFloat(1.16)),
                                (CGFloat(1), CGFloat(0.82))] {
            let centre = state.camera.project(
                Point3D(x: metrics.hingeHalfSpan * offset, y: y, z: z)
            )
            guard let bloom else { continue }
            context.saveGState()
            let r = reach * scale * centre.depthScale
            // Squashed: it is a stain in the plane of the case top, not a ball.
            context.translateBy(x: centre.point.x, y: centre.point.y)
            context.scaleBy(x: 1, y: 0.72)
            context.drawRadialGradient(
                bloom, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r,
                options: []
            )
            context.restoreGState()
        }
    }
}

// MARK: - The card

extension CompassRenderer {

    private func drawCard(in context: CGContext, state: State, metrics: CompassMetrics) {
        let radius = metrics.cardRadius
        let circlePath = CGMutablePath()
        circlePath.addLines(between: circle(radius, state))
        circlePath.closeSubpath()

        context.saveGState()
        context.addPath(circlePath)
        context.clip()

        // Paper: lit upper left, aged at the rim, browned where it meets brass.
        let light = CGPoint(x: -radius * 0.30, y: -radius * 0.36)
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CompassTheme.paperLit.cgColor,
                CompassTheme.paper.cgColor,
                CompassTheme.paperDeep.cgColor,
                CompassTheme.paperEdge.cgColor,
            ] as CFArray,
            locations: [0, 0.34, 0.72, 1]
        ) {
            context.drawRadialGradient(
                gradient,
                startCenter: light,
                startRadius: radius * 0.06,
                endCenter: .zero,
                endRadius: radius * 1.04,
                options: [.drawsBeforeStartLocation]
            )
        }

        grain.fill(in: context, scale: radius)
        drawRubRing(in: context, metrics: metrics)
        drawAgeing(in: context, state: state, metrics: metrics)
        drawSeatGrime(in: context, state: state, metrics: metrics)
        context.restoreGState()

        // A hairline where paper meets brass, so the seat reads as a gap not a blend.
        context.saveGState()
        context.addPath(circlePath)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.38).cgColor)
        context.setLineWidth(1)
        context.strokePath()
        context.restoreGState()
    }

    /// A century of the lid closing on the same spot has polished the paper just outside the
    /// hub. It is the wear mark that most says "used" rather than "reproduced".
    private func drawRubRing(in context: CGContext, metrics: CompassMetrics) {
        let radius = metrics.cardRadius
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor(calibratedWhite: 1, alpha: 0.10).cgColor,
                NSColor(calibratedWhite: 1, alpha: 0.05).cgColor,
                NSColor(calibratedWhite: 1, alpha: 0).cgColor,
            ] as CFArray,
            locations: [0, 0.5, 1]
        ) else { return }
        context.saveGState()
        context.drawRadialGradient(
            gradient,
            startCenter: .zero,
            startRadius: radius * 0.22,
            endCenter: .zero,
            endRadius: radius * 0.46,
            options: []
        )
        context.restoreGState()
    }

    /// Foxing and uneven ageing, so no two square inches of the card are the same tone.
    private func drawAgeing(in context: CGContext, state: State, metrics: CompassMetrics) {
        // Broad mottling first, under the sharp foxing: at a glance this is most of what makes
        // the card read as old paper rather than as a printed gradient.
        for blotch in grain.cardUnevenness(radius: metrics.cardRadius) {
            let point = state.camera.project(Point3D(
                x: blotch.x * metrics.cardRadius,
                y: blotch.y * metrics.cardRadius,
                z: metrics.cardDepth
            ))
            let radius = blotch.radius * metrics.cardRadius * point.depthScale
            let tone = NSColor(calibratedRed: 0.439, green: 0.314, blue: 0.165, alpha: 1)
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    tone.withAlphaComponent(blotch.alpha * CompassTheme.wearGain).cgColor,
                    tone.withAlphaComponent(0).cgColor,
                ] as CFArray,
                locations: [0, 1]
            ) else { continue }
            context.saveGState()
            context.translateBy(x: point.point.x, y: point.point.y)
            context.drawRadialGradient(
                gradient,
                startCenter: .zero, startRadius: 0,
                endCenter: .zero, endRadius: radius,
                options: []
            )
            context.restoreGState()
        }

        for spot in grain.ageSpots(radius: metrics.cardRadius) {
            let point = state.camera.project(Point3D(
                x: spot.x * metrics.cardRadius,
                y: spot.y * metrics.cardRadius,
                z: metrics.cardDepth
            ))
            let radius = spot.radius * metrics.cardRadius * point.depthScale
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    NSColor(calibratedRed: 0.478, green: 0.369, blue: 0.212, alpha: 1)
                        .withAlphaComponent(spot.alpha * CompassTheme.wearGain).cgColor,
                    NSColor(calibratedRed: 0.478, green: 0.369, blue: 0.212, alpha: 1).withAlphaComponent(0).cgColor,
                ] as CFArray,
                locations: [0, 1]
            ) else { continue }
            context.saveGState()
            context.translateBy(x: point.point.x, y: point.point.y)
            context.drawRadialGradient(
                gradient,
                startCenter: .zero,
                startRadius: 0,
                endCenter: .zero,
                endRadius: radius,
                options: []
            )
            context.restoreGState()
        }
    }

    /// Grime where the card has sat against the brass for decades: darkest at the very edge,
    /// heaviest at the bottom where dust settles.
    private func drawSeatGrime(in context: CGContext, state: State, metrics: CompassMetrics) {
        let radius = metrics.cardRadius
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor(calibratedRed: 0.259, green: 0.196, blue: 0.110, alpha: 1).withAlphaComponent(0).cgColor,
                NSColor(calibratedRed: 0.259, green: 0.196, blue: 0.110, alpha: 1).withAlphaComponent(0.10).cgColor,
                NSColor(calibratedRed: 0.208, green: 0.149, blue: 0.078, alpha: 1).withAlphaComponent(0.34).cgColor,
            ] as CFArray,
            locations: [0, 0.72, 1]
        ) else { return }
        context.saveGState()
        context.drawRadialGradient(
            gradient,
            startCenter: .zero,
            startRadius: radius * 0.80,
            endCenter: CGPoint(x: 0, y: radius * 0.05),
            endRadius: radius * 1.02,
            options: []
        )
        context.restoreGState()
    }
}
