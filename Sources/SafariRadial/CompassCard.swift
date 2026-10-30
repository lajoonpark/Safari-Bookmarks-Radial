import AppKit
import Foundation
import RadialCore

/// What is printed on the card, and the things that sit proud of it.
///
/// Split out from the case because it is a different material with different rules: paper is
/// flat and its ink follows the depth scale, while a slice's wash has to stay behind the ink
/// it is lighting up.
extension CompassRenderer {

    // MARK: - Printing

    func drawCardPrinting(in context: CGContext, state: State, metrics: CompassMetrics) {
        let z = metrics.cardDepth
        let alpha = CGFloat(state.contentAlpha)
        let layout = layout(for: state)

        drawGuilloche(in: context, state: state, metrics: metrics, alpha: alpha)
        drawScale(in: context, state: state, metrics: metrics, alpha: alpha)
        drawSectorRules(in: context, state: state, metrics: metrics, alpha: alpha)
        if state.showsNumbers {
            drawNumerals(in: context, state: state, metrics: metrics, layout: layout)
        }

        // Quadrant pips, in the gaps between the numerals.
        for degrees in [45.0, 135.0, 225.0, 315.0] {
            let angle = CGFloat(degrees) * .pi / 180
            let anchor = state.camera.project(
                x: metrics.numeralRadius * sin(angle),
                y: -metrics.numeralRadius * cos(angle),
                z: z
            )
            drawText(
                "·",
                at: anchor,
                scale: inkScale(at: Point3D(radius: metrics.numeralRadius, angle: angle), state),
                font: CompassTheme.serif(max(7, metrics.cardRadius * 0.050)),
                colour: CompassTheme.inkRule.withAlphaComponent(0.50 * alpha),
                in: context
            )
        }
    }

    /// Fine concentric circles in the margin between the sectors and the scale — the engraved
    /// band that stops the card reading as a blank disc with wedges printed on it.
    private func drawGuilloche(in context: CGContext, state: State, metrics: CompassMetrics, alpha: CGFloat) {
        for index in 0..<8 {
            let radius = metrics.sectorOutset + metrics.cardRadius * (0.005 + CGFloat(index) * 0.0075)
            let ring = (0...120).map { step -> CGPoint in
                let angle = CGFloat(step) / 120 * 2 * .pi
                return state.camera.project(x: radius * sin(angle), y: -radius * cos(angle), z: metrics.cardDepth)
            }
            stroke(ring, context,
                   CompassTheme.inkRule.withAlphaComponent((0.16 - CGFloat(index) * 0.012) * alpha),
                   width: 0.7)
        }
    }

    /// The printed degree scale, interrupted at each slot's bearing.
    ///
    /// The interruptions are not decoration: they are the gate each slot numeral sits in, and
    /// they are what let the numerals live on cream paper (9.3:1) instead of on brass (4.3:1).
    /// These digits are the keyboard shortcut, so they are the least affordable thing on the
    /// dial to misread.
    private func drawScale(in context: CGContext, state: State, metrics: CompassMetrics, alpha: CGFloat) {
        let z = metrics.cardDepth
        let sliceCount = max(1, state.slices.count)
        let stepDegrees = 360.0 / Double(sliceCount)

        for degrees in stride(from: 0, to: 360, by: CompassTheme.scaleStepDegrees) {
            let bearing = Double(degrees)
            var inGate = false
            for index in 0..<sliceCount {
                let centre = Double(index) * stepDegrees
                var delta = abs(bearing - centre).truncatingRemainder(dividingBy: 360)
                delta = min(delta, 360 - delta)
                if delta < stepDegrees * Double(CompassTheme.numeralGateHalf) {
                    inGate = true
                    break
                }
            }
            if inGate { continue }

            let angle = CGFloat(degrees) * .pi / 180
            let major = degrees % 15 == 0
            let inner = metrics.scaleInset + metrics.cardRadius * (major ? 0.008 : 0.032)
            let outer = metrics.scaleOutset
            let from = state.camera.project(x: inner * sin(angle), y: -inner * cos(angle), z: z)
            let to = state.camera.project(x: outer * sin(angle), y: -outer * cos(angle), z: z)
            line(from, to, context,
                 CompassTheme.inkRule.withAlphaComponent((major ? 0.55 : 0.26) * alpha),
                 width: major ? 1.05 : 0.7)
        }
    }

    /// The walls between slices: a dark hairline with a lit companion, so they read as cut
    /// into the paper rather than drawn over it.
    private func drawSectorRules(in context: CGContext, state: State, metrics: CompassMetrics, alpha: CGFloat) {
        let z = metrics.cardDepth
        let count = max(1, state.slices.count)
        let step = 2 * CGFloat.pi / CGFloat(count)
        for index in 0..<count {
            let angle = CGFloat(index) * step - step / 2
            let innerY = -(metrics.hubRadius + metrics.cardRadius * 0.02) * cos(angle)
            for (offset, colour, width) in [
                (CGFloat(1.7), NSColor.white.withAlphaComponent(0.40 * alpha), CGFloat(1.25)),
                (CGFloat(0), CompassTheme.inkRule.withAlphaComponent(0.42 * alpha), CGFloat(1.1)),
            ] {
                let from = state.camera.project(
                    x: (metrics.hubRadius + metrics.cardRadius * 0.02) * sin(angle),
                    y: innerY + offset,
                    z: z
                )
                let to = state.camera.project(
                    x: metrics.sectorOutset * sin(angle),
                    y: -metrics.sectorOutset * cos(angle) + offset,
                    z: z
                )
                line(from, to, context, colour, width: width)
            }
        }
    }

    /// The slot numerals, in their gates. The loudest ink on the card, because they are what
    /// the keyboard drives.
    private func drawNumerals(
        in context: CGContext,
        state: State,
        metrics: CompassMetrics,
        layout: RadialLayout
    ) {
        for index in 0..<max(1, state.slices.count) {
            let angle = layout.centerAngle(of: index)
            let hover = index < state.hover.count ? min(1, max(0, state.hover[index])) : 0
            let point = Point3D(radius: metrics.numeralRadius, angle: angle)
            let anchor = state.camera.project(x: point.x, y: point.y, z: metrics.cardDepth)
            drawText(
                RadialLayout.keyLabel(forSlice: index),
                at: anchor,
                scale: inkScale(at: point, state),
                font: CompassTheme.serif(max(8, metrics.cardRadius * 0.065), .semibold),
                colour: hover > 0.3
                    ? CompassTheme.vermilion.withAlphaComponent(0.55 + 0.45 * Double(hover))
                    : CompassTheme.ink.withAlphaComponent(0.94),
                in: context
            )
        }
    }

    // MARK: - Slices

    /// The aimed wedge's wash. Warm light on paper rather than a lit surface: the card is the
    /// material, so hovering has to read as a highlight washing over print.
    func drawSliceWash(in context: CGContext, state: State, metrics: CompassMetrics) {
        let layout = layout(for: state)
        let alpha = CGFloat(state.contentAlpha)
        for index in 0..<max(1, state.slices.count) {
            let hover = index < state.hover.count ? min(1, max(0, state.hover[index])) : 0
            guard hover > 0.008 else { continue }
            let path = wedge(
                index: index,
                inset: layout.step * 0.045,
                inner: metrics.sectorInset,
                outer: metrics.sectorOutset,
                layout: layout,
                state
            )
            context.saveGState()
            context.addPath(path)
            context.clip()
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    NSColor(calibratedRed: 0.808, green: 0.647, blue: 0.365, alpha: 1)
                        .withAlphaComponent(0.30 * hover * alpha).cgColor,
                    NSColor(calibratedRed: 0.847, green: 0.706, blue: 0.424, alpha: 1)
                        .withAlphaComponent(0.24 * hover * alpha).cgColor,
                    NSColor(calibratedRed: 0.902, green: 0.784, blue: 0.549, alpha: 1)
                        .withAlphaComponent(0.10 * hover * alpha).cgColor,
                ] as CFArray,
                locations: [0, 0.62, 1]
            ) {
                context.drawRadialGradient(
                    gradient,
                    startCenter: .zero,
                    startRadius: metrics.sectorInset,
                    endCenter: .zero,
                    endRadius: metrics.sectorOutset,
                    options: []
                )
            }
            context.restoreGState()

            // A vermilion rule along the aimed wedge's rim, so the aim has a crisp edge as well
            // as a wash — the wash alone is ambiguous on a bright wallpaper.
            if hover > 0.25 {
                let drawn = layout.drawableRange(of: index, inset: layout.step * 0.045)
                let arc = (0...24).map { step -> CGPoint in
                    let angle = drawn.start + drawn.sweep * CGFloat(step) / 24
                    return state.camera.project(
                        x: metrics.sectorOutset * sin(angle),
                        y: -metrics.sectorOutset * cos(angle),
                        z: metrics.cardDepth
                    )
                }
                stroke(arc, context,
                       CompassTheme.vermilion.withAlphaComponent(0.70 * Double(hover) * alpha),
                       width: 1.6)
            }
        }
    }

    // MARK: - The needle

    func drawNeedle(in context: CGContext, state: State, metrics: CompassMetrics) {
        let angle = state.needleAngle
        let z = metrics.cardDepth + metrics.cardRadius * 0.004
        let tip = metrics.cardRadius * 0.78
        let tail = metrics.cardRadius * 0.62
        let halfWidth = metrics.cardRadius * 0.026

        func at(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
            state.camera.project(
                x: along * sin(angle) - across * cos(angle),
                y: -along * cos(angle) - across * sin(angle),
                z: z
            )
        }

        let tipPoint = at(tip, 0)
        let leftPoint = at(0, -halfWidth)
        let backPoint = at(-tail, 0)
        let rightPoint = at(0, halfWidth)

        // A shadow a hair off, so the needle sits above the printing rather than in it.
        context.saveGState()
        context.translateBy(x: 1.1, y: 1.5)
        fill([tipPoint, leftPoint, backPoint, rightPoint], context,
             NSColor.black.withAlphaComponent(0.30))
        context.restoreGState()

        let path = CGMutablePath()
        path.addLines(between: [tipPoint, leftPoint, backPoint, rightPoint])
        path.closeSubpath()
        context.saveGState()
        context.addPath(path)
        context.clip()
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CompassTheme.vermilion.withAlphaComponent(0.8).cgColor,
                CompassTheme.vermilionLit.cgColor,
                CompassTheme.vermilion.cgColor,
            ] as CFArray,
            locations: [0, 0.5, 1]
        ) {
            context.drawLinearGradient(
                gradient,
                start: leftPoint,
                end: rightPoint,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        context.restoreGState()

        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.50).cgColor)
        context.setLineWidth(0.8)
        context.strokePath()
        context.restoreGState()
    }

    // MARK: - Labels

    func drawSliceLabels(in context: CGContext, state: State, metrics: CompassMetrics) {
        let layout = layout(for: state)
        let alpha = CGFloat(state.contentAlpha)
        let pageShift = CGFloat((1 - Easing.outCubic(min(1, max(0, state.pageAlpha)))) * 9)
        // Where the sweep's leading edge is, as a fraction of a turn clockwise from 12 o'clock. It is
        // the same easing `drawSweep` uses, so each label lights as the edge reaches its bearing.
        let edge = Easing.outQuint(min(1, max(0, state.sweep)))

        for index in 0..<max(1, state.slices.count) {
            guard let bookmark = state.slices[safe: index] else { continue }
            let hover = index < state.hover.count ? min(1, max(0, state.hover[index])) : 0
            let angle = layout.centerAngle(of: index)
            let radius = metrics.labelRadius
            let point = Point3D(radius: radius, angle: angle)
            let anchor = state.camera.project(x: point.x, y: point.y, z: metrics.cardDepth)
            let scale = inkScale(at: point, state)

            // The labels come in clockwise with the sweep. The reveal is measured against the edge scaled
            // by 1.22, so the last slot (a bearing under one turn) is fully inked before the sweep settles,
            // and slot 1 (bearing 0) starts dark. A hovered label is never dimmed by that.
            let bearing = Double(RadialLayout.normalize(angle)) / (2 * .pi)
            let revealed = Easing.smoothstep(min(1, max(0, (1.22 * edge - bearing) / 0.22)))
            let labelAlpha = alpha * CGFloat(max(Double(hover), revealed))

            // Ask the *same* layout the hit test uses how wide a box fits inside this wedge.
            let boxHeight: CGFloat = bookmark.subtitle.isEmpty ? 20 : 34
            let limit = layout.labelWidthLimit(for: index, radius: radius, height: boxHeight, pad: 7)
            let maxWidth = max(34, min(limit, metrics.cardRadius * 0.60))

            let title = fittedTitle(
                bookmark.displayTitle,
                maxWidth: maxWidth,
                hover: hover,
                alpha: labelAlpha,
                metrics: metrics
            )

            context.saveGState()
            // Clip to the wedge: glyph metrics vary with the font actually installed, and the
            // wedge is the authority on where a slice ends.
            context.addPath(wedge(
                index: index,
                inset: 0.05,
                inner: metrics.sectorInset,
                outer: metrics.sectorOutset,
                layout: layout,
                state
            ))
            context.clip()

            let box = CGRect(
                x: anchor.x - maxWidth / 2,
                y: anchor.y - title.size().height / 2 + pageShift - (bookmark.subtitle.isEmpty ? 0 : 6 * scale),
                width: maxWidth,
                height: title.size().height
            )
            draw(squashed: title, in: box, scale: scale, context: context)

            if !bookmark.subtitle.isEmpty, maxWidth >= 44 {
                let subtitle = NSAttributedString(string: bookmark.subtitle, attributes: [
                    .font: CompassTheme.serif(max(6, metrics.cardRadius * 0.040)),
                    .foregroundColor: CompassTheme.inkSubtle
                        .withAlphaComponent((0.90 + 0.10 * Double(hover)) * Double(labelAlpha)),
                ])
                let subBox = CGRect(
                    x: anchor.x - maxWidth / 2,
                    y: box.maxY + 1,
                    width: maxWidth,
                    height: 14
                )
                draw(squashed: subtitle, in: subBox, scale: scale, context: context)
            }
            context.restoreGState()
        }
    }

    /// Largest size that fits the wedge on one line, with truncation as the backstop.
    ///
    /// Shrinking before truncating is what keeps "Apple Developer" whole at nine slices, where
    /// a fixed 13pt title would clip to "Apple Devel…".
    private func fittedTitle(
        _ text: String,
        maxWidth: CGFloat,
        hover: CGFloat,
        alpha: CGFloat,
        metrics: CompassMetrics
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail

        let base = max(8, metrics.cardRadius * 0.065)
        var chosen = NSAttributedString(string: text)
        for step in stride(from: 0, through: 10, by: 1) {
            let size = base - CGFloat(step) * (base * 0.05)
            guard size > metrics.cardRadius * 0.038 else { break }
            let string = NSAttributedString(string: text, attributes: [
                .font: CompassTheme.serif(size, .semibold),
                .foregroundColor: CompassTheme.ink
                    .withAlphaComponent((0.86 + 0.14 * Double(hover)) * Double(alpha)),
                .paragraphStyle: paragraph,
            ])
            chosen = string
            if string.size().width <= maxWidth { break }
        }
        return chosen
    }

    // MARK: - Hub

    func drawHub(in context: CGContext, state: State, metrics: CompassMetrics) {
        let radius = metrics.hubRadius
        let hover = min(1, max(0, state.hubHover))
        let boss = CGMutablePath()
        boss.addLines(between: circle(radius, state))
        boss.closeSubpath()

        context.saveGState()
        context.addPath(boss)
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CompassTheme.brassLit.cgColor,
                CompassTheme.brassMid.cgColor,
                CompassTheme.brassDark.cgColor,
                CompassTheme.brassDeep.cgColor,
            ] as CFArray,
            locations: [0, 0.34, 0.72, 1]
        ) {
            context.clip()
            context.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: -radius * 0.34, y: -radius * 0.42),
                startRadius: radius * 0.05,
                endCenter: .zero,
                endRadius: radius * 1.10,
                options: []
            )
            context.resetClip()
        }
        context.restoreGState()

        context.saveGState()
        context.addPath(boss)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        context.setLineWidth(1)
        context.strokePath()
        context.restoreGState()

        // The readout window: the aimed slot, in the most legible ink on the instrument.
        let window = CGMutablePath()
        window.addLines(between: circle(metrics.hubWindowRadius, state))
        window.closeSubpath()
        context.saveGState()
        context.addPath(window)
        context.setFillColor(CompassTheme.hubWindow.cgColor)
        context.fillPath()
        context.addPath(window)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.10 + 0.20 * Double(hover)).cgColor)
        context.setLineWidth(1)
        context.strokePath()
        context.restoreGState()

        let aimed = state.hoveredSlice
        let readout = aimed.map { String(format: "%02d", $0 + 1) } ?? "–"
        drawText(
            readout,
            at: .zero,
            scale: 1,
            font: CompassTheme.serif(radius * 0.62, .semibold),
            colour: CompassTheme.hubWindowInk,
            in: context
        )

        // Close affordance: an engraved ✕ that appears only when the hub is aimed at.
        if hover > 0.02 {
            let arm = radius * 0.30
            context.saveGState()
            context.rotate(by: hover * .pi / 4)
            context.setStrokeColor(CompassTheme.hubWindowInk.withAlphaComponent(0.92 * Double(hover)).cgColor)
            context.setLineWidth(max(1.5, radius * 0.055))
            context.setLineCap(.round)
            context.move(to: CGPoint(x: -arm, y: -arm))
            context.addLine(to: CGPoint(x: arm, y: arm))
            context.move(to: CGPoint(x: arm, y: -arm))
            context.addLine(to: CGPoint(x: -arm, y: arm))
            context.strokePath()
            context.restoreGState()
        }
    }

    // MARK: - Opening sweep

    /// One orchestrated gesture as the compass appears: a needle of light runs once around the
    /// card and expires, explaining the clockwise order in a single beat.
    func drawSweep(in context: CGContext, state: State, metrics: CompassMetrics) {
        let progress = state.sweep
        guard progress > 0.002, progress < 0.998 else { return }
        let eased = Easing.outQuint(min(1, progress))
        // Slot 1 sits at 12 o'clock (`RadialLayout.centerAngle(of: 0)` is 0), so the sweep starts there
        // and runs clockwise, the same way the slots are numbered.
        let start: CGFloat = 0
        let end = start + 2 * .pi * CGFloat(eased)
        let radius = metrics.numeralRadius
        let fade = CGFloat(1 - Easing.outCubic(min(1, progress)))

        let arc = (0...48).map { step -> CGPoint in
            let angle = start + (end - start) * CGFloat(step) / 48
            return state.camera.project(
                x: radius * sin(angle), y: -radius * cos(angle), z: metrics.cardDepth
            )
        }
        stroke(arc, context,
               CompassTheme.vermilion.withAlphaComponent(0.85 * fade * CGFloat(state.contentAlpha)),
               width: 2)
    }

    // MARK: - Helpers

    /// The layout the dial has always used, so labels, hit testing and keyboard firing cannot
    /// disagree about where a slice is.
    private func layout(for state: State) -> RadialLayout {
        RadialLayout(
            sliceCount: max(1, state.slices.count),
            centerRadius: state.metrics.hubRadius,
            outerRadius: state.metrics.sectorOutset
        )
    }

    /// Draws type at the depth scale of its anchor and squeezes it vertically, so it lies on
    /// the leaning card instead of floating above it.
    private func draw(squashed string: NSAttributedString, in box: CGRect, scale: CGFloat, context: CGContext) {
        context.saveGState()
        context.translateBy(x: box.midX, y: box.midY)
        context.scaleBy(x: 1, y: max(0.5, scale))
        string.draw(with: CGRect(
            x: -box.width / 2,
            y: -box.height / 2,
            width: box.width,
            height: box.height
        ), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        context.restoreGState()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
