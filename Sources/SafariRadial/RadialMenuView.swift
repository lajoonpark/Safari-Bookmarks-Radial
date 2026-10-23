import AppKit
import Foundation
import RadialCore

/// Draws and animates the radial dial.
///
/// Geometry comes from `RadialLayout` (unit tested); this view only handles pixels, springs
/// and input. Two rules keep it from looking generic:
///
/// 1. Every animated value is a spring or an eased scalar, so nothing moves linearly.
/// 2. The aimed wedge is the only element allowed to be saturated, and it *lifts* — the whole
///    wedge, its edge and its label move together along the slice's own bearing, like a key
///    rising on a keyboard.
final class RadialMenuView: NSView {

    // MARK: - Model

    private(set) var bookmarks: [Bookmark] = []
    private(set) var page = 0
    private(set) var paging = RadialPaging(total: 0)
    var showsNumbers = true
    var menuRadius: CGFloat = 200

    var onActivate: ((Bookmark) -> Void)?
    var onClose: (() -> Void)?
    var onClickOutside: (() -> Void)?

    // MARK: - Animation state

    private let driver = FrameDriver()
    private var openProgress = SpringValue(0, stiffness: 300, damping: 24)
    private var contentProgress = SpringValue(0, stiffness: 250, damping: 26)
    /// The compass sweep that plays once as the dial appears.
    private var sweepProgress = SpringValue(0, stiffness: 260, damping: 34)
    private var sliceHover: [SpringValue] = []
    private var slicePress: [SpringValue] = []
    private var hubHover = SpringValue(0, stiffness: 380, damping: 28)
    private var hubPress = SpringValue(0, stiffness: 500, damping: 30)
    private var pageSwap = SpringValue(0, stiffness: 420, damping: 30)
    private var needle = SpringValue(0, stiffness: 300, damping: 26)

    private var hoveredSlice: Int?
    private var pressedSlice: Int?
    private var pressedHub = false
    private var pressStartedOutside = false
    private var trackingArea: NSTrackingArea?
    private var isClosing = false

    /// Where the hub sits in view coordinates.
    var ringCenter: CGPoint?

    private var ringOrigin: CGPoint {
        ringCenter ?? CGPoint(x: bounds.midX, y: bounds.midY)
    }

    private var ringLayout: RadialLayout {
        RadialLayout(sliceCount: bookmarks.count, centerRadius: hubDiameter / 2, outerRadius: menuRadius)
    }

    /// One bookmark is not a ring, so the hub is not drawn and the radius is not used.
    private var isSolo: Bool { bookmarks.count == 1 }

    private var hubDiameter: CGFloat { max(84, menuRadius * 0.46) }
    private var scaleFactor: CGFloat { max(0.78, min(1.0, menuRadius / 200)) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Lifecycle

    func configure(bookmarks: [Bookmark], page: Int, paging: RadialPaging, showsNumbers: Bool, radius: CGFloat) {
        self.bookmarks = bookmarks
        self.page = page
        self.paging = paging
        self.showsNumbers = showsNumbers
        self.menuRadius = radius
        resizeSprings(count: bookmarks.count)
        resetHover()
        needsDisplay = true
    }

    func present() {
        isClosing = false
        openProgress.snap(to: 0)
        contentProgress.snap(to: 0)
        sweepProgress.snap(to: 0)
        openProgress.target = 1
        contentProgress.target = 1
        sweepProgress.target = 1
        needle.snap(to: Double(ringLayout.centerAngle(of: 0)))
        primeHoverFromPointer()
        beginAnimating()
    }

    /// The dial opens under the cursor, so whatever slice is there should already be lit
    /// and the needle should already point at it.
    private func primeHoverFromPointer() {
        let point = convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
        let relative = relativePoint(point)
        let hit = isSolo ? soloHit(relative) : ringLayout.hitTest(relative)
        switch hit {
        case .slice(let index) where index < bookmarks.count:
            hoveredSlice = index
            needle.snap(to: Double(ringLayout.centerAngle(of: index)))
            hubHover.snap(to: 0)
        case .close where !isSolo:
            hoveredSlice = nil
            hubHover.snap(to: 1)
        default:
            hoveredSlice = nil
            hubHover.snap(to: 0)
            needle.snap(to: Double(ringLayout.centerAngle(of: 0)))
        }
        for index in sliceHover.indices {
            sliceHover[index].snap(to: index == hoveredSlice ? 1 : 0)
        }
        hubHover.target = hit == .close && !isSolo ? 1 : 0
    }

    func dismiss(animated: Bool, completion: (() -> Void)? = nil) {
        guard !isClosing else { return }
        isClosing = true
        hoveredSlice = nil
        pressedSlice = nil
        pressedHub = false
        releasePressSprings()
        if animated {
            openProgress.target = 0
            contentProgress.target = 0
            beginAnimating()
            // Matches the close spring: the panel must not vanish mid-animation.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                completion?()
            }
        } else {
            openProgress.snap(to: 0)
            completion?()
        }
    }

    func updatePage(bookmarks: [Bookmark], page: Int, paging: RadialPaging) {
        self.bookmarks = bookmarks
        self.page = page
        self.paging = paging
        resizeSprings(count: bookmarks.count)
        resetHover()
        needle.snap(to: Double(ringLayout.centerAngle(of: 0)))
        pageSwap.snap(to: 0)
        pageSwap.target = 1
        beginAnimating()
    }

    private func resizeSprings(count: Int) {
        if sliceHover.count != count {
            sliceHover = (0..<count).map { _ in SpringValue(0, stiffness: 420, damping: 30) }
            slicePress = (0..<count).map { _ in SpringValue(0, stiffness: 520, damping: 34) }
        }
    }

    private func resetHover() {
        hoveredSlice = nil
        for index in sliceHover.indices {
            sliceHover[index].target = 0
            slicePress[index].target = 0
        }
        hubHover.target = 0
    }

    // MARK: - Animation loop

    private func beginAnimating() {
        driver.start { [weak self] dt in
            self?.advance(dt)
        }
    }

    private func advance(_ dt: Double) {
        var moving = false

        openProgress.step(dt)
        contentProgress.step(dt)
        sweepProgress.step(dt)
        hubHover.step(dt)
        hubPress.step(dt)
        pageSwap.step(dt)
        needle.step(dt)
        if openProgress.isAnimating || contentProgress.isAnimating || sweepProgress.isAnimating
            || hubHover.isAnimating || hubPress.isAnimating || pageSwap.isAnimating || needle.isAnimating {
            moving = true
        }

        for index in sliceHover.indices {
            sliceHover[index].step(dt)
            slicePress[index].step(dt)
            if sliceHover[index].isAnimating || slicePress[index].isAnimating { moving = true }
        }

        needsDisplay = true

        if !moving {
            driver.stop()
            if isClosing { isClosing = false }
        }
    }

    // MARK: - Pointer handling

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        handlePointer(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hoveredSlice = nil
        applyHoverTargets()
    }

    private func handlePointer(_ point: CGPoint) {
        let relative = relativePoint(point)
        let hit = isSolo ? soloHit(relative) : ringLayout.hitTest(relative)

        let newHover: Int?
        switch hit {
        case .slice(let index) where index < bookmarks.count:
            newHover = index
        default:
            newHover = nil
        }

        if newHover != hoveredSlice {
            hoveredSlice = newHover
            applyHoverTargets()
        }
        if let newHover {
            needle.target = Double(ringLayout.centerAngle(of: newHover))
        }
        hubHover.target = (hit == .close && !isSolo) ? 1 : 0
        beginAnimating()
    }

    /// A slice fired from the keyboard should spring back out, not stay held down.
    private func releasePressSprings() {
        for index in slicePress.indices {
            slicePress[index].target = 0
        }
        hubPress.target = 0
    }

    private func applyHoverTargets() {
        for index in sliceHover.indices {
            sliceHover[index].target = (index == hoveredSlice) ? 1 : 0
        }
        beginAnimating()
    }

    override func mouseDown(with event: NSEvent) {
        let relative = relativePoint(convert(event.locationInWindow, from: nil))
        let hit = isSolo ? soloHit(relative) : ringLayout.hitTest(relative)

        pressStartedOutside = false
        switch hit {
        case .close:
            pressedHub = true
            hubPress.target = 1
            beginAnimating()
        case .slice(let index) where index < bookmarks.count:
            pressedSlice = index
            slicePress[index].target = 1
            beginAnimating()
        default:
            pressStartedOutside = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let relative = relativePoint(convert(event.locationInWindow, from: nil))
        let hit = isSolo ? soloHit(relative) : ringLayout.hitTest(relative)

        let closedOnHub = pressedHub
        if pressedHub { hubPress.target = 0 }

        if let pressed = pressedSlice {
            slicePress[pressed].target = 0
            pressedSlice = nil
            // Only fire when the pointer is released over the same slice: dragging off
            // cancels, which is what people expect from a menu.
            if case .slice(let index) = hit, index == pressed, index < bookmarks.count {
                fire(index)
                releasePressSprings()
                beginAnimating()
                return
            }
        }
        beginAnimating()

        if closedOnHub {
            pressedHub = false
            pressStartedOutside = false
            if hit == .close {
                onClose?()
                return
            }
        }

        if hit == .none && pressStartedOutside {
            onClickOutside?()
        }
        pressedHub = false
        pressStartedOutside = false
    }

    /// The solo card is a rectangle, so it needs its own hit test rather than a wedge test.
    private func soloHit(_ relative: CGPoint) -> RadialLayout.Hit {
        guard !bookmarks.isEmpty else { return .none }
        return soloCardRect().contains(relative) ? .slice(0) : .none
    }

    private func soloCardRect() -> CGRect {
        // Wide enough for the number disc on the left and a real title on the right; narrow
        // enough that a single link still looks like one slot rather than a banner.
        let width = min(400, max(330, menuRadius * 1.75))
        let height: CGFloat = 96
        return CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
    }

    private func relativePoint(_ point: CGPoint) -> CGPoint {
        let origin = ringOrigin
        return CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    private func fire(_ index: Int) {
        guard index < bookmarks.count else { return }
        onActivate?(bookmarks[index])
    }

    /// Keyboard-driven press feedback, so keys and clicks feel like the same action.
    func flashSlice(_ index: Int) {
        guard slicePress.indices.contains(index) else { return }
        slicePress[index].snap(to: 1.4)
        slicePress[index].target = 0
        beginAnimating()
    }

// MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let center = ringOrigin
        let open = openProgress.value
        guard open > 0.001 else { return }

        let appear = Easing.outCubic(min(1, max(0, open)))
        let content = Easing.outCubic(min(1, max(0, contentProgress.value)))

        drawBackdrop(in: context, center: center, alpha: appear)

        // Ring space: origin at the hub centre, y down. The open animation scales this whole
        // space, so text stays crisp because it is measured after the transform.
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        let scale = 0.88 + 0.12 * CGFloat(Easing.outBack(appear, overshoot: 1.3))
        context.scaleBy(x: scale, y: scale)

        if bookmarks.isEmpty {
            drawEmptyState(alpha: content)
        } else if isSolo {
            drawSoloCard(in: context, alpha: content)
        } else {
            drawSlices(in: context, contentAlpha: content)
            if showsNumbers { drawBezel(in: context, contentAlpha: content) }
            drawHub(in: context, contentAlpha: content)
        }

        drawSweep(in: context, alpha: content)
        context.restoreGState()

        if paging.pageCount > 1 {
            drawPagePips(in: context, center: center, alpha: content)
        }
        drawHints(in: context, center: center, alpha: content)
    }

    private func drawBackdrop(in context: CGContext, center: CGPoint, alpha: Double) {
        // A soft scrim under the dial only. Dimming the whole screen would make this a modal;
        // keeping it local keeps it an overlay you can still see past.
        let outer = max(menuRadius * 1.9, 320)
        let colors = [
            RadialTheme.backdropInner.withAlphaComponent(RadialTheme.backdropAlpha * CGFloat(alpha)).cgColor,
            RadialTheme.backdropInner.withAlphaComponent(RadialTheme.backdropMidAlpha * CGFloat(alpha)).cgColor,
            RadialTheme.backdropInner.withAlphaComponent(0).cgColor,
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 0.55, 1] as [CGFloat]
        ) else { return }
        context.saveGState()
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: outer,
            options: []
        )
        context.restoreGState()
    }

    // MARK: Slices

    private func drawSlices(in context: CGContext, contentAlpha: Double) {
        let layout = ringLayout
        guard !bookmarks.isEmpty else { return }

        // Aimed wedge last, so its lift overlaps its neighbours instead of being clipped by them.
        for index in bookmarks.indices where index != hoveredSlice {
            drawSlice(in: context, index: index, layout: layout, contentAlpha: contentAlpha)
        }
        if let hovered = hoveredSlice, bookmarks.indices.contains(hovered) {
            drawSlice(in: context, index: hovered, layout: layout, contentAlpha: contentAlpha)
        }
    }

    private func drawSlice(in context: CGContext, index: Int, layout: RadialLayout, contentAlpha: Double) {
        guard let bookmark = bookmarks[safe: index] else { return }
        let hover = sliceHover[safe: index]?.value ?? 0
        let press = slicePress[safe: index]?.value ?? 0
        let h = CGFloat(min(1, max(0, hover)))

        // Hover and press widen the wedge slightly, so the target grows under the cursor.
        let gap = min(0.014, layout.step * 0.045)
        let drawn = layout.drawableRange(of: index, inset: gap - h * 0.003 - CGFloat(press) * 0.003)
        let inner = layout.innerRadius + 2 - h * 3
        let outer = layout.outerRadius - 2 - CGFloat(press) * 4
        guard drawn.sweep > 0.002 else { return }

        let angle = layout.centerAngle(of: index)
        let lift = RadialTheme.hoverLift * h
        let offset = CGPoint(x: sin(angle) * lift, y: -cos(angle) * lift)
        let path = wedgePath(start: drawn.start, sweep: drawn.sweep, inner: inner, outer: outer, layout: layout)

        context.saveGState()
        context.translateBy(x: offset.x, y: offset.y)

        // Warm light spilling out from behind the aimed wedge. It reads as the dial lighting
        // that slot up rather than as a highlight painted on it, which is the difference
        // between an instrument and a pie chart.
        if h > 0.02 {
            let glowRadius = outer + 30
            let colors = [
                RadialTheme.signal.withAlphaComponent(Double(RadialTheme.aimGlowAlpha) * Double(h)).cgColor,
                RadialTheme.signal.withAlphaComponent(0).cgColor,
            ] as CFArray
            if let glow = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0.42, 1] as [CGFloat]
            ) {
                let anchor = layout.point(radius: (inner + outer) / 2, angle: angle)
                context.saveGState()
                context.drawRadialGradient(
                    glow,
                    startCenter: anchor,
                    startRadius: inner * 0.4,
                    endCenter: anchor,
                    endRadius: glowRadius,
                    options: []
                )
                context.restoreGState()
            }
        }

        // A darker silhouette under a lifted wedge. Deterministic at any scale, and one fill
        // instead of a blur pass.
        if h > 0.02 {
            let castPath = wedgePath(
                start: drawn.start, sweep: drawn.sweep,
                inner: inner + 1.5, outer: outer + 2.5, layout: layout
            )
            context.saveGState()
            context.translateBy(x: 1.5, y: 2.5)
            context.addPath(castPath)
            context.setFillColor(NSColor.black.withAlphaComponent(0.45 * h).cgColor)
            context.fillPath()
            context.restoreGState()
        }

        // Body: deepest at the hub, lit at the rim, so the ring reads as one lit dial.
        context.saveGState()
        context.addPath(path)
        context.clip()
        let near = blend(RadialTheme.sliceNear, RadialTheme.sliceNearHover, t: Double(h))
        let mid = blend(RadialTheme.sliceMid, RadialTheme.sliceMidHover, t: Double(h))
        let far = blend(RadialTheme.sliceFar, RadialTheme.sliceFarHover, t: Double(h))
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [near.cgColor, mid.cgColor, far.cgColor] as CFArray,
            locations: [0, 0.72, 1] as [CGFloat]
        ) {
            let a = layout.point(radius: inner, angle: angle)
            let b = layout.point(radius: outer, angle: angle)
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: a.x, y: a.y),
                end: CGPoint(x: b.x, y: b.y),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        context.restoreGState()

        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(
            (h > 0.02
                ? RadialTheme.sliceStrokeHover.withAlphaComponent(0.30 + 0.45 * h)
                : RadialTheme.sliceStroke
            ).cgColor
        )
        context.setLineWidth(h > 0.02 ? 1.2 : 1)
        context.setLineJoin(.round)
        context.strokePath()
        context.restoreGState()

        // A short bright tick on the rim marks the aimed slice. Narrow wedges get a tick
        // instead of a full rail, because a rail along a 40° wedge reads as an outline.
        if h > 0.02 && bookmarks.count > 3 {
            let half = min(0.16, layout.step * 0.22)
            context.saveGState()
            context.addArc(
                center: .zero,
                radius: outer + 5,
                startAngle: angle - half,
                endAngle: angle + half,
                clockwise: false
            )
            context.setStrokeColor(RadialTheme.signal.withAlphaComponent(0.9 * h).cgColor)
            context.setLineWidth(2)
            context.setLineCap(.round)
            context.strokePath()
            context.restoreGState()
        }

        context.restoreGState()

        drawSliceLabel(
            in: context,
            bookmark: bookmark,
            index: index,
            layout: layout,
            hover: h,
            alpha: contentAlpha,
            offset: offset,
            pageAlpha: pageSwap.value
        )
    }
}

// MARK: - Drawing: labels, bezel, hub

extension RadialMenuView {

    private func drawSliceLabel(
        in context: CGContext,
        bookmark: Bookmark,
        index: Int,
        layout: RadialLayout,
        hover: CGFloat,
        alpha: Double,
        offset: CGPoint,
        pageAlpha: Double
    ) {
        let angle = layout.centerAngle(of: index)
        let radius = layout.labelRadius + RadialTheme.labelLift * hover
        let anchor = layout.point(radius: radius, angle: angle)
        let slide = CGFloat((1 - Easing.outCubic(min(1, max(0, pageAlpha)))) * 9)

        // Ask the layout how wide a box fits inside this wedge at this height. That is why a
        // label at 3 o'clock no longer pushes through the slice wall: the wedge's horizontal
        // room varies with its bearing, so the limit is bisected against the wedge itself.
        let subtitleText = bookmark.subtitle
        let boxHeight: CGFloat = subtitleText.isEmpty ? 20 : 34
        let maxWidth = max(48, layout.labelWidthLimit(
            for: index, radius: radius, height: boxHeight, pad: 7
        ))

        let title = fitTitle(bookmark.displayTitle, maxWidth: maxWidth, hover: hover, alpha: alpha)
        let centreX = anchor.x + offset.x
        var cursorY = anchor.y + offset.y + slide - boxHeight / 2

        // The box is bisected against the wedge, but its width still comes from the measured
        // string, and glyph metrics are not the same on every machine or display scale. The
        // wedge itself is the authority, so the label is clipped to it: text can never cross a
        // slice wall, whatever the font does.
        context.saveGState()
        let drawn = layout.drawableRange(of: index, inset: 0.05)
        context.addPath(wedgePath(
            start: drawn.start, sweep: drawn.sweep,
            inner: layout.innerRadius, outer: layout.outerRadius, layout: layout
        ))
        context.clip()

        title.string.draw(
            with: CGRect(x: centreX - maxWidth / 2, y: cursorY, width: maxWidth, height: title.height),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        )
        cursorY += title.height

        guard !subtitleText.isEmpty, maxWidth >= 34, subtitleFits(subtitleText, maxWidth: maxWidth) else {
            context.restoreGState()
            return
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: RadialTheme.subtitleFont(size: 9.5 * scaleFactor),
            .foregroundColor: blend(
                RadialTheme.subtitleInk, RadialTheme.subtitleInkHover, t: Double(hover)
            ).withAlphaComponent(CGFloat(alpha)),
            .paragraphStyle: paragraph,
        ]
        NSAttributedString(string: subtitleText, attributes: attributes).draw(
            with: CGRect(x: centreX - maxWidth / 2, y: cursorY + 2, width: maxWidth, height: 13),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        )
        context.restoreGState()
    }

    /// Largest title size that fits the wedge on one line, with truncation as the backstop.
    ///
    /// Shrinking before truncating keeps names like "OpenRouter" whole at nine slices, where a
    /// fixed 12.5pt title would be clipped to "OpenRout…".
    private func fitTitle(
        _ text: String,
        maxWidth: CGFloat,
        hover: CGFloat,
        alpha: Double
    ) -> (string: NSAttributedString, height: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let ink = blend(RadialTheme.titleInk, RadialTheme.titleInkHover, t: Double(hover))
            .withAlphaComponent(CGFloat(alpha))

        var chosen = (NSAttributedString(string: text), CGFloat(18))
        for size in [13.5, 13.0, 12.5, 12.0, 11.5, 11.0, 10.5, 10.0] as [CGFloat] {
            let scaled = size * scaleFactor
            let string = NSAttributedString(string: text, attributes: [
                .font: RadialTheme.titleFont(size: scaled),
                .foregroundColor: ink,
                .paragraphStyle: paragraph,
            ])
            chosen = (string, ceil(scaled * 1.24))
            if string.size().width <= maxWidth { break }
        }
        return chosen
    }

    private func subtitleFits(_ text: String, maxWidth: CGFloat) -> Bool {
        let font = RadialTheme.subtitleFont(size: 9.5 * scaleFactor)
        if (text as NSString).size(withAttributes: [.font: font]).width <= maxWidth { return true }
        // A truncated host name ("mail.google…") still tells you where you are going, so it
        // is kept; only hiding it when there is almost no room avoids a row of ellipses.
        return maxWidth >= 44
    }

    private func drawBezel(in context: CGContext, contentAlpha: Double) {
        // The engraved scale is what makes the dial read as an instrument rather than a pie
        // chart: sixty fine ticks and one long tick on each slice's centre line, with the slot
        // numbers printed on a band just outside it.
        //
        // The band is not decoration. Digits sitting straight on the desktop were the first
        // thing to disappear against a bright window or a photo wallpaper, and the band is the
        // ring's own material extended outward so a number always has something to sit on.
        let layout = ringLayout
        let bandInner = layout.outerRadius + RadialTheme.bezelBandInset
        let bandOuter = bandInner + RadialTheme.bezelBandWidth

        context.saveGState()
        context.addArc(center: .zero, radius: bandInner, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        context.addArc(center: .zero, radius: bandOuter, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        context.setFillColor(RadialTheme.bezelBandFill.withAlphaComponent(RadialTheme.bezelBandFill.alphaComponent * CGFloat(contentAlpha)).cgColor)
        context.fillPath()
        context.setStrokeColor(
            RadialTheme.bezelTickInk.withAlphaComponent(min(1, CGFloat(contentAlpha) * 1.4)).cgColor
        )
        context.setLineWidth(1)
        context.addArc(center: .zero, radius: bandInner, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        context.strokePath()
        context.addArc(center: .zero, radius: bandOuter, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        context.strokePath()
        context.restoreGState()

        let innerR = layout.outerRadius + RadialTheme.bezelTickInnerGap
        let tickCount = RadialTheme.bezelTickCount

        // The long ticks sit on the slice centre lines, so each one lines up with its number.
        // They must be placed by their own angles rather than picked off the minor grid: with
        // nine slices the centres fall on 40° steps, which never land on a 6° tick.
        let boundaries = (0..<max(1, layout.sliceCount)).map { layout.centerAngle(of: $0) }
        func isBoundary(_ angle: CGFloat) -> Bool {
            boundaries.contains { boundary in
                let delta = abs(RadialLayout.normalize(angle) - RadialLayout.normalize(boundary))
                return min(delta, 2 * .pi - delta) < 0.02
            }
        }

        for tick in 0..<tickCount {
            let angle = CGFloat(tick) / CGFloat(tickCount) * 2 * .pi
            guard !isBoundary(angle) else { continue }
            let a = layout.point(radius: innerR, angle: angle)
            let b = layout.point(radius: innerR + RadialTheme.bezelMinorTick, angle: angle)
            context.saveGState()
            context.setStrokeColor(RadialTheme.bezelTickInk.withAlphaComponent(CGFloat(contentAlpha)).cgColor)
            context.setLineWidth(1)
            context.move(to: CGPoint(x: a.x, y: a.y))
            context.addLine(to: CGPoint(x: b.x, y: b.y))
            context.strokePath()
            context.restoreGState()
        }

        for boundary in boundaries {
            let a = layout.point(radius: innerR, angle: boundary)
            let b = layout.point(radius: innerR + RadialTheme.bezelMajorTick, angle: boundary)
            context.saveGState()
            context.setStrokeColor(RadialTheme.bezelTickMajorInk.withAlphaComponent(CGFloat(contentAlpha)).cgColor)
            context.setLineWidth(1)
            context.move(to: CGPoint(x: a.x, y: a.y))
            context.addLine(to: CGPoint(x: b.x, y: b.y))
            context.strokePath()
            context.restoreGState()
        }

        // Numbers, centred on each slice's bearing. Hovering a wedge lights its number, so the
        // band doubles as a readout of which slot the needle is over.
        let numberRadius = bandInner + RadialTheme.bezelBandWidth / 2
        for index in 0..<max(1, layout.sliceCount) {
            let hover = CGFloat(min(1, max(0, sliceHover[safe: index]?.value ?? 0)))
            let string = NSAttributedString(
                string: RadialLayout.keyLabel(forSlice: index),
                attributes: [
                    .font: RadialTheme.bezelFont(size: 10.5, weight: hover > 0.3 ? .semibold : .medium),
                    .foregroundColor: (hover > 0.3 ? RadialTheme.signal : RadialTheme.bezelNumberInk)
                        .withAlphaComponent(CGFloat(contentAlpha)),
                ]
            )
            let anchor = layout.point(radius: numberRadius, angle: layout.centerAngle(of: index))
            let size = string.size()
            string.draw(at: CGPoint(x: anchor.x - size.width / 2, y: anchor.y - size.height / 2))
        }
    }

    private func drawHub(in context: CGContext, contentAlpha: Double) {
        let radius = hubDiameter / 2
        let hover = CGFloat(min(1, max(0, hubHover.value)))
        let press = CGFloat(min(1, max(0, hubPress.value)))
        let effective = radius * (1 + 0.04 * hover - 0.06 * press)
        let rect = CGRect(x: -effective, y: -effective, width: effective * 2, height: effective * 2)

        context.saveGState()
        let top = blend(RadialTheme.hubFillTop, RadialTheme.hubFillTopHover, t: Double(hover))
        let bottom = blend(RadialTheme.hubFillBottom, RadialTheme.hubFillBottomHover, t: Double(hover))
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [top.cgColor, bottom.cgColor] as CFArray,
            locations: [0, 1] as [CGFloat]
        ) {
            context.addEllipse(in: rect)
            context.clip()
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: -effective),
                end: CGPoint(x: 0, y: effective),
                options: []
            )
            context.resetClip()
        }
        context.restoreGState()

        context.saveGState()
        context.setStrokeColor(RadialTheme.hubBorder.withAlphaComponent(0.55 + 0.30 * hover).cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: rect)
        context.restoreGState()

        let aimed = hoveredSlice.flatMap { bookmarks.indices.contains($0) ? $0 : nil }
        if let aimed, hover < 0.6 {
            let fade = 1 - hover / 0.6
            drawNeedle(in: context, radius: effective, fade: fade)
            drawHubReadout(
                in: context,
                radius: effective,
                alpha: Double(fade) * contentAlpha,
                index: aimed
            )
        } else if aimed == nil && hover < 0.3 {
            drawHubIdle(
                in: context,
                radius: effective,
                alpha: Double((1 - hover / 0.3) * 0.55) * contentAlpha
            )
        }

        if hover > 0.02 {
            drawHubClose(in: context, radius: effective, hover: Double(hover))
        }
    }

    /// A thin bearing line from the rim to a small arrowhead, rotating with the aimed slice.
    private func drawNeedle(in context: CGContext, radius: CGFloat, fade: CGFloat) {
        context.saveGState()
        context.rotate(by: CGFloat(needle.value))
        let tip = -radius * 0.86
        context.setStrokeColor(RadialTheme.signal.withAlphaComponent(0.55 * fade).cgColor)
        context.setLineWidth(1.6)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: 0, y: tip))
        context.addLine(to: CGPoint(x: 0, y: -radius * 0.30))
        context.strokePath()

        context.move(to: CGPoint(x: 0, y: tip - 5))
        context.addLine(to: CGPoint(x: 4.2, y: tip + 4))
        context.addLine(to: CGPoint(x: -4.2, y: tip + 4))
        context.closePath()
        context.setFillColor(RadialTheme.signal.withAlphaComponent(0.95 * fade).cgColor)
        context.fillPath()
        context.restoreGState()
    }

    private func drawHubReadout(in context: CGContext, radius: CGFloat, alpha: Double, index: Int) {
        let discRadius = radius * 0.42
        let rect = CGRect(
            x: -discRadius, y: -discRadius,
            width: discRadius * 2, height: discRadius * 2
        )
        context.saveGState()
        context.setFillColor(RadialTheme.hubReadoutDisc.withAlphaComponent(CGFloat(alpha)).cgColor)
        context.fillEllipse(in: rect)
        context.setStrokeColor(RadialTheme.signal.withAlphaComponent(0.22 * CGFloat(alpha)).cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: rect)

        let string = NSAttributedString(
            string: String(RadialLayout.keyLabel(forSlice: index)).leftPadded(to: 2),
            attributes: [
                .font: RadialTheme.bezelFont(size: radius * 0.44, weight: .semibold),
                .foregroundColor: RadialTheme.signal.withAlphaComponent(CGFloat(alpha)),
            ]
        )
        let size = string.size()
        string.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
        context.restoreGState()
    }

    private func drawHubIdle(in context: CGContext, radius: CGFloat, alpha: Double) {
        let string = NSAttributedString(
            string: "esc",
            attributes: [
                .font: RadialTheme.bezelFont(size: max(9, radius * 0.20), weight: .medium),
                .foregroundColor: NSColor(calibratedRed: 0.949, green: 0.918, blue: 0.863, alpha: CGFloat(alpha)),
            ]
        )
        let size = string.size()
        string.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
    }

    private func drawHubClose(in context: CGContext, radius: CGFloat, hover: Double) {
        // The ✕ rotates 45° as the hub is hovered: a close control that announces itself.
        let arm = radius * 0.26
        context.saveGState()
        context.rotate(by: CGFloat(hover) * .pi / 4)
        context.setStrokeColor(RadialTheme.signal.withAlphaComponent(0.92 * hover).cgColor)
        context.setLineWidth(max(1.7, radius * 0.07))
        context.setLineCap(.round)
        context.move(to: CGPoint(x: -arm, y: -arm))
        context.addLine(to: CGPoint(x: arm, y: arm))
        context.move(to: CGPoint(x: arm, y: -arm))
        context.addLine(to: CGPoint(x: -arm, y: arm))
        context.strokePath()
        context.restoreGState()
    }
}

// MARK: - Drawing: solo card, sweep, furniture

extension RadialMenuView {

    /// One bookmark is still a dial, not a lonely donut.
    ///
    /// A 360° wedge with a single label reads as a smear, and a floating card next to nothing
    /// reads as a different product. So the solo state keeps the instrument: an arc of the
    /// bezel's tick scale runs behind a single slot, the slot is stamped with its number in a
    /// key disc, and the hub's job — "this is what 1 does" — moves into that disc.
    private func drawSoloCard(in context: CGContext, alpha: Double) {
        guard let bookmark = bookmarks.first else { return }
        let hover = CGFloat(min(1, max(0, sliceHover.first?.value ?? 0)))
        let rect = soloCardRect()
        let lift = 7 * hover

        drawSoloHalo(in: context, rect: rect, alpha: alpha, hover: hover)

        if hover > 0.02 {
            let center = CGPoint(x: 0, y: -lift)
            let colors = [
                RadialTheme.signal.withAlphaComponent(Double(RadialTheme.aimGlowAlpha) * Double(hover)).cgColor,
                RadialTheme.signal.withAlphaComponent(0).cgColor,
            ] as CFArray
            if let glow = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0.3, 1] as [CGFloat]
            ) {
                context.drawRadialGradient(
                    glow,
                    startCenter: center,
                    startRadius: 20,
                    endCenter: center,
                    endRadius: rect.width * 0.78,
                    options: []
                )
            }
        }

        let body = CGPath(roundedRect: rect, cornerWidth: 15, cornerHeight: 15, transform: nil)

        context.saveGState()
        context.translateBy(x: 0, y: -lift)
        context.setShadow(
            offset: CGSize(width: 0, height: 8),
            blur: 24,
            color: NSColor.black.withAlphaComponent(0.5 * CGFloat(alpha)).cgColor
        )
        context.addPath(body)
        context.setFillColor(NSColor(calibratedRed: 0.043, green: 0.129, blue: 0.149, alpha: CGFloat(alpha)).cgColor)
        context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)

        context.addPath(body)
        context.clip()
        let left = blend(
            NSColor(calibratedRed: 0.039, green: 0.125, blue: 0.145, alpha: 1),
            NSColor(calibratedRed: 0.102, green: 0.282, blue: 0.298, alpha: 1),
            t: Double(hover)
        )
        let right = blend(
            NSColor(calibratedRed: 0.063, green: 0.173, blue: 0.196, alpha: 1),
            NSColor(calibratedRed: 0.173, green: 0.376, blue: 0.369, alpha: 1),
            t: Double(hover)
        )
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [left.cgColor, right.cgColor] as CFArray,
            locations: [0, 1] as [CGFloat]
        ) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.minX, y: rect.minY),
                end: CGPoint(x: rect.maxX, y: rect.maxY),
                options: []
            )
        }
        context.resetClip()

        context.addPath(body)
        context.setStrokeColor(
            (hover > 0.02 ? RadialTheme.signal.withAlphaComponent(0.75) : RadialTheme.sliceStroke).cgColor
        )
        context.setLineWidth(hover > 0.02 ? 1.4 : 1)
        context.strokePath()
        context.restoreGState()

        let textLeft = drawSoloKeyDisc(
            in: context,
            rect: rect,
            lift: lift,
            hover: hover,
            alpha: alpha
        )

        let maxWidth = rect.maxX - textLeft - 26
        NSAttributedString(
            string: bookmark.displayTitle,
            attributes: [
                .font: RadialTheme.titleFont(size: 16 * scaleFactor),
                .foregroundColor: RadialTheme.titleInkHover.withAlphaComponent(CGFloat(alpha)),
            ]
        ).draw(
            with: CGRect(x: textLeft, y: -lift - 16, width: maxWidth, height: 20),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        )

        if !bookmark.subtitle.isEmpty {
            NSAttributedString(
                string: bookmark.subtitle,
                attributes: [
                    .font: RadialTheme.subtitleFont(size: 10.5 * scaleFactor),
                    .foregroundColor: (hover > 0.4 ? RadialTheme.subtitleInkHover : RadialTheme.subtitleInk)
                        .withAlphaComponent(CGFloat(alpha)),
                ]
            ).draw(
                with: CGRect(x: textLeft, y: -lift + 8, width: maxWidth, height: 14),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
            )
        }

    }

    /// The bezel's tick scale, wrapped around a single slot. It is the same engraving as the
    /// nine-slice dial, so the solo state still looks like this app and not like a card.
    ///
    /// The scale is elliptical because the slot is: a circle at this radius would cut through
    /// the card's own edges.
    private func drawSoloHalo(in context: CGContext, rect: CGRect, alpha: Double, hover: CGFloat) {
        let radiusX = rect.width / 2 + 13
        let radiusY = rect.height / 2 + 15
        let tickCount = 72
        // Leave the bottom open: a closed ring around one card reads as a zero.
        let start = CGFloat.pi * -0.84
        let sweep = CGFloat.pi * 1.68
        for tick in 0...tickCount {
            let t = CGFloat(tick) / CGFloat(tickCount)
            let angle = start + sweep * t
            let major = tick % 9 == 0
            let inset = major ? CGFloat(11) : CGFloat(6)
            let from = CGPoint(x: radiusX * sin(angle), y: -radiusY * cos(angle))
            let to = CGPoint(x: (radiusX + inset) * sin(angle), y: -(radiusY + inset) * cos(angle))
            let ink = major ? RadialTheme.bezelTickMajorInk : RadialTheme.bezelTickInk
            context.saveGState()
            context.setStrokeColor(ink.withAlphaComponent(CGFloat(alpha) * (0.8 + 0.8 * Double(hover))).cgColor)
            context.setLineWidth(1)
            context.move(to: from)
            context.addLine(to: to)
            context.strokePath()
            context.restoreGState()
        }

    }

    /// Number disc on the left edge of the solo slot, drawn like the hub readout.
    private func drawSoloKeyDisc(
        in context: CGContext,
        rect: CGRect,
        lift: CGFloat,
        hover: CGFloat,
        alpha: Double
    ) -> CGFloat {
        let diameter: CGFloat = 48
        let center = CGPoint(x: rect.minX + 24 + diameter / 2, y: -lift)
        let disc = CGRect(
            x: center.x - diameter / 2, y: center.y - diameter / 2,
            width: diameter, height: diameter
        )

        context.saveGState()
        context.setFillColor(
            RadialTheme.hubReadoutDisc.withAlphaComponent(CGFloat(alpha) * (0.9 + 0.1 * hover)).cgColor
        )
        context.fillEllipse(in: disc)
        context.setStrokeColor(
            (hover > 0.02
                ? RadialTheme.signal.withAlphaComponent(0.75)
                : RadialTheme.hubBorder
            ).cgColor
        )
        context.setLineWidth(hover > 0.02 ? 1.4 : 1)
        context.strokeEllipse(in: disc)
        context.restoreGState()

        let numeral = NSAttributedString(
            string: RadialLayout.keyLabel(forSlice: 0),
            attributes: [
                .font: RadialTheme.bezelFont(size: 19 * scaleFactor, weight: .semibold),
                .foregroundColor: (hover > 0.02 ? RadialTheme.signal : RadialTheme.titleInk)
                    .withAlphaComponent(CGFloat(alpha)),
            ]
        )
        let size = numeral.size()
        numeral.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))

        context.saveGState()
        context.setStrokeColor(RadialTheme.sliceStroke.withAlphaComponent(CGFloat(alpha)).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: disc.maxX + 16, y: -lift - 17))
        context.addLine(to: CGPoint(x: disc.maxX + 16, y: -lift + 17))
        context.strokePath()
        context.restoreGState()

        return disc.maxX + 32
    }

    /// One orchestrated gesture as the dial appears: a signal arc runs once around the bezel
    /// and expires. It explains the ring's direction — clockwise from twelve — in a single beat.
    private func drawSweep(in context: CGContext, alpha: Double) {
        let t = sweepProgress.value
        guard t > 0.002, t < 0.998 else { return }
        let eased = Easing.outQuint(min(1, t))
        let start = -CGFloat.pi / 2
        let end = start + 2 * .pi * CGFloat(eased)
        let radius = ringLayout.outerRadius + RadialTheme.bezelTickInnerGap
        let fade = CGFloat(1 - Easing.outCubic(min(1, t)))

        context.saveGState()
        context.setStrokeColor(RadialTheme.signal.withAlphaComponent(0.85 * fade * CGFloat(alpha)).cgColor)
        context.setLineWidth(2)
        context.setLineCap(.round)
        context.addArc(center: .zero, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        context.strokePath()

        let tip = ringLayout.point(radius: radius, angle: end + .pi / 2)
        context.setFillColor(RadialTheme.signal.withAlphaComponent(fade * CGFloat(alpha)).cgColor)
        context.fillEllipse(in: CGRect(x: tip.x - 2.4, y: tip.y - 2.4, width: 4.8, height: 4.8))
        context.restoreGState()
    }

    private func drawPagePips(in context: CGContext, center: CGPoint, alpha: Double) {
        let count = paging.pageCount
        let spacing: CGFloat = 15
        let y = center.y + menuRadius + 74
        let totalWidth = CGFloat(count - 1) * spacing

        for page in 0..<count {
            let x = center.x - totalWidth / 2 + CGFloat(page) * spacing
            let isCurrent = page == self.page
            let string = NSAttributedString(
                string: "\(page + 1)",
                attributes: [
                    .font: RadialTheme.bezelFont(size: 10, weight: isCurrent ? .semibold : .medium),
                    .foregroundColor: (isCurrent ? RadialTheme.signal : RadialTheme.footerInk)
                        .withAlphaComponent(CGFloat(alpha)),
                ]
            )
            let size = string.size()
            string.draw(at: CGPoint(x: x - size.width / 2, y: y - size.height / 2))

            if isCurrent {
                context.saveGState()
                context.setStrokeColor(RadialTheme.signal.withAlphaComponent(0.8 * CGFloat(alpha)).cgColor)
                context.setLineWidth(1.5)
                context.setLineCap(.round)
                context.move(to: CGPoint(x: x - 4, y: y + 8))
                context.addLine(to: CGPoint(x: x + 4, y: y + 8))
                context.strokePath()
                context.restoreGState()
            }
        }
    }

    private func drawHints(in context: CGContext, center: CGPoint, alpha: Double) {
        // The key hint names the keys that are actually live: on a three-slot dial, "1–9"
        // promises six slots that do not exist.
        let keys = bookmarks.count == 1 ? "1" : "1–\(bookmarks.count)"
        let labels: [String]
        if isSolo {
            labels = [keys, "click", "esc"]
        } else if paging.pageCount > 1 {
            labels = ["← →", keys, "esc"]
        } else {
            labels = [keys, "esc"]
        }

        let font = RadialTheme.bezelFont(size: 10.5, weight: .medium)
        let height: CGFloat = 20
        let gap: CGFloat = 7
        let widths = labels.map { label -> CGFloat in
            max(20, (label as NSString).size(withAttributes: [.font: font]).width + 14)
        }
        let total = widths.reduce(0, +) + gap * CGFloat(labels.count - 1)
        let y = isSolo
            ? center.y + 72
            : center.y + menuRadius + (paging.pageCount > 1 ? 104 : 66)

        var x = center.x - total / 2
        for (index, label) in labels.enumerated() {
            let width = widths[index]
            let rect = CGRect(x: x, y: y - height / 2, width: width, height: height)
            let path = CGPath(roundedRect: rect, cornerWidth: 5, cornerHeight: 5, transform: nil)
            context.saveGState()
            context.addPath(path)
            context.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.05 * CGFloat(alpha)).cgColor)
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(RadialTheme.bezelTickInk.withAlphaComponent(CGFloat(alpha)).cgColor)
            context.setLineWidth(1)
            context.strokePath()
            context.restoreGState()

            let string = NSAttributedString(
                string: label,
                attributes: [
                    .font: font,
                    .foregroundColor: RadialTheme.footerInk.withAlphaComponent(CGFloat(alpha)),
                ]
            )
            let size = string.size()
            string.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))

            x += width + gap
        }
    }

    private func drawEmptyState(alpha: Double) {
        let title = NSAttributedString(
            string: "No bookmarks yet",
            attributes: [
                .font: RadialTheme.titleFont(size: 15 * scaleFactor),
                .foregroundColor: RadialTheme.titleInk.withAlphaComponent(CGFloat(alpha)),
            ]
        )
        let subtitle = NSAttributedString(
            string: "Add one from the menu bar",
            attributes: [
                .font: RadialTheme.subtitleFont(size: 10.5 * scaleFactor),
                .foregroundColor: RadialTheme.subtitleInk.withAlphaComponent(CGFloat(alpha)),
            ]
        )
        let titleSize = title.size()
        let subtitleSize = subtitle.size()
        title.draw(at: CGPoint(x: -titleSize.width / 2, y: -18))
        subtitle.draw(at: CGPoint(x: -subtitleSize.width / 2, y: 4))
    }
}

// MARK: - Drawing helpers

extension RadialMenuView {

    private func wedgePath(start: CGFloat, sweep: CGFloat, inner: CGFloat, outer: CGFloat,
                           layout: RadialLayout) -> CGPath {
        let path = CGMutablePath()
        let segments = max(2, Int((sweep / (.pi / 24)).rounded(.up)))
        path.move(to: layout.point(radius: outer, angle: start))
        for step in 1...segments {
            let t = CGFloat(step) / CGFloat(segments)
            path.addLine(to: layout.point(radius: outer, angle: start + sweep * t))
        }
        for step in stride(from: segments, through: 0, by: -1) {
            let t = CGFloat(step) / CGFloat(segments)
            path.addLine(to: layout.point(radius: inner, angle: start + sweep * t))
        }
        path.closeSubpath()
        return path
    }

    private func blend(_ a: NSColor, _ b: NSColor, t: Double) -> NSColor {
        guard let a = a.usingColorSpace(.deviceRGB), let b = b.usingColorSpace(.deviceRGB) else { return a }
        let amount = CGFloat(min(1, max(0, t)))
        return NSColor(
            red: a.redComponent + (b.redComponent - a.redComponent) * amount,
            green: a.greenComponent + (b.greenComponent - a.greenComponent) * amount,
            blue: a.blueComponent + (b.blueComponent - a.blueComponent) * amount,
            alpha: a.alphaComponent + (b.alphaComponent - a.alphaComponent) * amount
        )
    }
}

private extension String {
    /// "1" → "01", so the hub readout does not change width as you move around the dial.
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: "0", count: width - count) + self
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}



