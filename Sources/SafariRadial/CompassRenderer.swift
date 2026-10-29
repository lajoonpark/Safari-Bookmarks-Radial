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
        var contentAlpha: Double
        var sweep: Double
        var pageAlpha: Double
    }

    private let grain = CompassGrain()

    func draw(_ state: State, in context: CGContext, at centre: CGPoint) {
        let m = state.metrics

        context.saveGState()
        context.translateBy(x: centre.x, y: centre.y)

        drawScrim(in: context, state: state)
        drawContactShadow(in: context, state: state)
        drawLidShadow(in: context, state: state)

        // From here down everything is in card space: origin at the hub, y down, projected.
        drawLid(in: context, state: state)
        drawCaseWall(in: context, state: state, metrics: m)
        drawLug(in: context, state: state, metrics: m)
        drawBrass(in: context, state: state, metrics: m)
        drawHinge(in: context, state: state, metrics: m)
        drawCard(in: context, state: state, metrics: m)
        drawCardPrinting(in: context, state: state, metrics: m)
        drawSliceWash(in: context, state: state, metrics: m)
        drawNeedle(in: context, state: state, metrics: m)
        drawSliceLabels(in: context, state: state, metrics: m)
        drawHub(in: context, state: state, metrics: m)
        drawSweep(in: context, state: state, metrics: m)

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
        let alpha = state.contentAlpha
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

    private func drawContactShadow(in context: CGContext, state: State) {
        let m = state.metrics
        let radius = m.caseRadius * 1.5
        let centre = CGPoint(x: 0, y: m.caseRadius * 0.12)
        let colours = [
            NSColor.black.withAlphaComponent(0.62 * CGFloat(state.contentAlpha)).cgColor,
            NSColor.black.withAlphaComponent(0.30 * CGFloat(state.contentAlpha)).cgColor,
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

    /// The lid casts onto the card. Without it an open lid reads as pasted on rather than
    /// hinged, which is the difference the whole illusion turns on.
    private func drawLidShadow(in context: CGContext, state: State) {
        let openness = state.lid.openness
        guard openness > 0.02 else { return }
        let m = state.metrics
        let lift = sin(min(.pi, state.lid.angle))
        let centre = CGPoint(x: 0, y: -m.caseRadius * 0.86)
        let spread = m.caseRadius * (0.95 - 0.25 * lift)
        let colours = [
            NSColor.black.withAlphaComponent(0.34 * lift * CGFloat(state.contentAlpha)).cgColor,
            NSColor.black.withAlphaComponent(0.16 * lift * CGFloat(state.contentAlpha)).cgColor,
            NSColor.black.withAlphaComponent(0).cgColor,
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colours,
            locations: [0, 0.55, 1] as [CGFloat]
        ) else { return }
        context.saveGState()
        context.translateBy(x: centre.x, y: centre.y)
        context.drawRadialGradient(
            gradient,
            startCenter: .zero,
            startRadius: spread * 0.1,
            endCenter: .zero,
            endRadius: spread,
            options: []
        )
        context.restoreGState()
    }
}

// MARK: - The lid

extension CompassRenderer {

    private func drawLid(in context: CGContext, state: State) {
        let lid = state.lid
        guard lid.openness > 0.004 else { return }
        let m = state.metrics
        let radius = lid.radius
        let alpha = CGFloat(state.contentAlpha)

        func lidPoint(_ angle: CGFloat, _ r: CGFloat) -> CGPoint {
            let flat = Point3D(radius: r, angle: angle)
            return state.camera.project(lid.swing(flat)).point
        }

        let rim = (0...90).map { lidPoint(CGFloat($0) / 90 * 2 * .pi, radius) }

        // Underside: the same disc nudged, so a thickness shows on the edge that turns away.
        context.saveGState()
        context.translateBy(x: 0, y: -m.cardRadius * 0.026 * sin(lid.angle))
        fill(rim, context, CompassTheme.brassDeep.withAlphaComponent(alpha))
        context.restoreGState()

        // Face.
        fill(rim, context, CompassTheme.brassLit.withAlphaComponent(alpha))

        // Interior recess, clipped to the lid.
        context.saveGState()
        let clip = CGMutablePath()
        clip.addLines(between: rim)
        clip.closeSubpath()
        context.addPath(clip)
        context.clip()

        let recess = (0...80).map { lidPoint(CGFloat($0) / 80 * 2 * .pi, radius * 0.80) }
        let recessPath = CGMutablePath()
        recessPath.addLines(between: recess)
        recessPath.closeSubpath()
        let top = state.camera.project(lid.swing(Point3D(x: 0, y: lid.hingeY - radius, z: 0))).point
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CompassTheme.lidRecessInner.withAlphaComponent(alpha).cgColor,
                CompassTheme.lidRecessOuter.withAlphaComponent(alpha).cgColor,
            ] as CFArray,
            locations: [0, 1] as [CGFloat]
        ) {
            context.saveGState()
            context.addPath(recessPath)
            context.clip()
            context.drawRadialGradient(
                gradient,
                startCenter: top,
                startRadius: radius * 0.1,
                endCenter: top,
                endRadius: radius * 0.85,
                options: []
            )
            context.restoreGState()
        }

        // Turning circles: the lathe marks a spun lid carries.
        for step in 1...7 {
            let ring = (0...70).map { lidPoint(CGFloat($0) / 70 * 2 * .pi, radius * 0.80 * CGFloat(step) / 7.4) }
            stroke(ring, context,
                   NSColor.black.withAlphaComponent((0.10 + 0.02 * CGFloat(step)) * alpha),
                   width: 0.9)
        }

        // Maker's mark, engraved on the inside of the lid.
        let mark = NSAttributedString(string: "SAFARI  RADIAL", attributes: [
            .font: CompassTheme.serif(max(6, radius * 0.042), .semibold),
            .foregroundColor: CompassTheme.brassHi.withAlphaComponent(0.52 * alpha),
            .kern: radius * 0.007,
        ])
        let markSize = mark.size()
        mark.draw(at: CGPoint(x: top.x - markSize.width / 2, y: top.y - radius * 0.16))
        context.restoreGState()

        // Lit rim where the lid turns toward the light.
        stroke(rim, context,
               NSColor.white.withAlphaComponent((0.06 + 0.22 * max(0, sin(lid.angle))) * alpha),
               width: 1.1)
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
        let alpha = CGFloat(state.contentAlpha)
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
            (outer, NSColor.black.withAlphaComponent(0.60 * alpha), CGFloat(1.2)),
            (inner, NSColor.black.withAlphaComponent(0.50 * alpha), CGFloat(1.3)),
            (inner * 0.986, NSColor.white.withAlphaComponent(0.13 * alpha), CGFloat(1)),
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
        let alpha = CGFloat(state.contentAlpha)
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
                    CompassTheme.patina.withAlphaComponent(blot.alpha * alpha).cgColor,
                    CompassTheme.patina.withAlphaComponent(blot.alpha * 0.55 * alpha).cgColor,
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
        let alpha = CGFloat(state.contentAlpha)
        for buff in grain.buffs(radius: metrics.cardRadius) {
            let from = state.camera.project(Point3D(x: buff.radius * sin(buff.angle), y: -buff.radius * cos(buff.angle), z: metrics.cardDepth))
            let to = state.camera.project(Point3D(x: buff.radius * sin(buff.angle + buff.length), y: -buff.radius * cos(buff.angle + buff.length), z: metrics.cardDepth))
            context.saveGState()
            context.setStrokeColor(CompassTheme.brassHi.withAlphaComponent(buff.alpha * alpha).cgColor)
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
        let alpha = CGFloat(state.contentAlpha)
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CompassTheme.patina.withAlphaComponent(0).cgColor,
                CompassTheme.patina.withAlphaComponent(0.16 * alpha).cgColor,
                CompassTheme.patina.withAlphaComponent(0.30 * alpha).cgColor,
            ] as CFArray,
            locations: [0, 0.65, 1]
        ) else { return }
        context.saveGState()
        context.drawRadialGradient(
            gradient,
            startCenter: .zero,
            startRadius: outer * 0.93,
            endCenter: .zero,
            endRadius: outer,
            options: []
        )
        context.restoreGState()
    }

    /// The knurled edge: alternating lit and shadowed ridges, drawn from the card's plane so
    /// they lean with everything else.
    private func drawReeding(in context: CGContext, state: State, metrics: CompassMetrics) {
        let outer = metrics.caseRadius
        let alpha = CGFloat(state.contentAlpha)
        let count = 190
        context.saveGState()
        for index in 0..<count {
            let angle = CGFloat(index) / CGFloat(count) * 2 * .pi
            let from = state.camera.project(Point3D(x: outer * 0.952 * sin(angle), y: -outer * 0.952 * cos(angle), z: metrics.cardDepth))
            let to = state.camera.project(Point3D(x: outer * sin(angle), y: -outer * cos(angle), z: metrics.cardDepth))
            let lit = index % 2 == 0
            context.setStrokeColor(
                (lit ? NSColor.white.withAlphaComponent(0.15) : NSColor.black.withAlphaComponent(0.22))
                    .withAlphaComponent((lit ? 0.15 : 0.22) * alpha)
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
        let alpha = CGFloat(state.contentAlpha)
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
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.55 * alpha).cgColor)
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
        stroke(highlight, context, NSColor.white.withAlphaComponent(0.40 * alpha), width: 1.1)
        context.restoreGState()
    }

    /// The hinge barrel across the top of the case. It is what makes the open lid read as
    /// attached rather than floating above the box.
    private func drawHinge(in context: CGContext, state: State, metrics: CompassMetrics) {
        let alpha = CGFloat(state.contentAlpha)
        let y = -metrics.caseRadius
        let z = -metrics.cardDepth * 0.5

        let shaftFrom = state.camera.project(Point3D(x: -metrics.hingeHalfSpan * 1.11, y: y, z: z))
        let shaftTo = state.camera.project(Point3D(x: metrics.hingeHalfSpan * 1.11, y: y, z: z))
        context.saveGState()
        context.setStrokeColor(CompassTheme.brassMid.withAlphaComponent(alpha).cgColor)
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
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.50 * alpha).cgColor)
            context.setLineWidth(0.9)
            context.strokePath()
            context.restoreGState()
        }
    }
}

// MARK: - The card

extension CompassRenderer {

    private func drawCard(in context: CGContext, state: State, metrics: CompassMetrics) {
        let radius = metrics.cardRadius
        let alpha = CGFloat(state.contentAlpha)
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
                options: []
            )
        }

        grain.fill(in: context, scale: radius)
        drawRubRing(in: context, metrics: metrics, alpha: alpha)
        drawAgeing(in: context, state: state, metrics: metrics)
        drawSeatGrime(in: context, state: state, metrics: metrics)
        context.restoreGState()

        // A hairline where paper meets brass, so the seat reads as a gap not a blend.
        context.saveGState()
        context.addPath(circlePath)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.38 * alpha).cgColor)
        context.setLineWidth(1)
        context.strokePath()
        context.restoreGState()
    }

    /// A century of the lid closing on the same spot has polished the paper just outside the
    /// hub. It is the wear mark that most says "used" rather than "reproduced".
    private func drawRubRing(in context: CGContext, metrics: CompassMetrics, alpha: CGFloat) {
        let radius = metrics.cardRadius
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor(calibratedWhite: 1, alpha: 0.10 * alpha).cgColor,
                NSColor(calibratedWhite: 1, alpha: 0.05 * alpha).cgColor,
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
        let alpha = CGFloat(state.contentAlpha)
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
                        .withAlphaComponent(spot.alpha * alpha).cgColor,
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
        let alpha = CGFloat(state.contentAlpha)
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor(calibratedRed: 0.259, green: 0.196, blue: 0.110, alpha: 1).withAlphaComponent(0).cgColor,
                NSColor(calibratedRed: 0.259, green: 0.196, blue: 0.110, alpha: 1).withAlphaComponent(0.10 * alpha).cgColor,
                NSColor(calibratedRed: 0.208, green: 0.149, blue: 0.078, alpha: 1).withAlphaComponent(0.34 * alpha).cgColor,
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
