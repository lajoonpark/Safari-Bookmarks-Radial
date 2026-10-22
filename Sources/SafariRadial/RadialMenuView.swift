import AppKit
import Foundation
import RadialCore

/// Draws and animates the radial menu.
///
/// Geometry comes from `RadialLayout` (unit tested); this view only handles pixels, springs
/// and input. Everything animated is a spring or an eased scalar so that no motion is linear.
final class RadialMenuView: NSView {

    // MARK: - Model

    private(set) var bookmarks: [Bookmark] = []
    private(set) var page = 0
    private(set) var paging = RadialPaging(total: 0)
    var showsNumbers = true
    var menuRadius: CGFloat = 200

    /// Called when the pointer or keyboard picks a slice.
    var onActivate: ((Bookmark) -> Void)?
    var onClose: (() -> Void)?
    var onClickOutside: (() -> Void)?

    // MARK: - Animation state

    private let driver = FrameDriver()
    private var openProgress = SpringValue(0, stiffness: 320, damping: 22)
    private var contentProgress = SpringValue(0, stiffness: 280, damping: 24)
    private var sliceHover: [SpringValue] = []
    private var slicePress: [SpringValue] = []
    private var hubHover = SpringValue(0, stiffness: 380, damping: 28)
    private var hubPress = SpringValue(0, stiffness: 500, damping: 30)
    private var pageSwap = SpringValue(0, stiffness: 420, damping: 30)

    private var hoveredSlice: Int?
    private var pressedSlice: Int?
    private var pressedHub = false
    private var pressStartedOutside = false
    private var trackingArea: NSTrackingArea?

    private var isClosing = false

    /// Where the hub sits in view coordinates. The controller clamps this so the whole ring
    /// stays on screen when the cursor is near an edge.
    var ringCenter: CGPoint?

    private var ringOrigin: CGPoint {
        ringCenter ?? CGPoint(x: bounds.midX, y: bounds.midY)
    }

    private var ringLayout: RadialLayout {
        RadialLayout(sliceCount: bookmarks.count, centerRadius: hubDiameter / 2, outerRadius: menuRadius)
    }

    private var hubDiameter: CGFloat { max(76, menuRadius * 0.48) }
    private var scaleFactor: CGFloat { max(0.72, min(1.0, menuRadius / 200)) }

    /// The panel is nonactivating, so the click that lands right after it appears must not be
    /// swallowed as an "activation" click.
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
        openProgress.target = 1
        contentProgress.target = 1
        primeHoverFromPointer()
        beginAnimating()
    }

    /// The menu opens under the cursor, so whatever slice is there should already be lit.
    private func primeHoverFromPointer() {
        let point = convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
        let hit = ringLayout.hitTest(relativePoint(point))
        switch hit {
        case .slice(let index) where index < bookmarks.count:
            hoveredSlice = index
            hubHover.snap(to: 0)
        case .close:
            hoveredSlice = nil
            hubHover.snap(to: 1)
        default:
            hoveredSlice = nil
            hubHover.snap(to: 0)
        }
        for index in sliceHover.indices {
            sliceHover[index].snap(to: index == hoveredSlice ? 1 : 0)
        }
        hubHover.target = hit == .close ? 1 : 0
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
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
        pageSwap.snap(to: 0)
        pageSwap.target = 1
        beginAnimating()
    }

    private func resizeSprings(count: Int) {
        if sliceHover.count != count {
            sliceHover = (0..<count).map { _ in
                SpringValue(0, stiffness: 420, damping: 30)
            }
            slicePress = (0..<count).map { _ in
                SpringValue(0, stiffness: 500, damping: 32)
            }
        }
    }

    private func resetHover() {
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
        hubHover.step(dt)
        hubPress.step(dt)
        pageSwap.step(dt)
        if openProgress.isAnimating || contentProgress.isAnimating
            || hubHover.isAnimating || hubPress.isAnimating || pageSwap.isAnimating {
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
            if isClosing {
                isClosing = false
            }
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
        let hit = ringLayout.hitTest(relative)

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
        hubHover.target = (hit == .close) ? 1 : 0
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

        let hit = ringLayout.hitTest(relative)
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
        let hit = ringLayout.hitTest(relative)

        let closedOnHub = pressedHub
        if pressedHub { hubPress.target = 0 }

        if let pressed = pressedSlice {
            slicePress[pressed].target = 0
            pressedSlice = nil
            // Only fire when the pointer is released over the same slice: dragging off cancels,
            // which is what people expect from a menu.
            if case .slice(let index) = hit, index == pressed, index < bookmarks.count {
                fire(index)
                // The view is about to be torn down, but in key-focus-kept flows it is not.
                releasePressSprings()
                beginAnimating()
                return
            }
        }
        beginAnimating()

        // The hub is only a close button if press and release both land on it.
        if closedOnHub {
            pressedHub = false
            pressStartedOutside = false
            if hit == .close {
                onClose?()
                return
            }
        }

        if hit == .none && pressStartedOutside {
            // A click on empty space outside the ring dismisses, like any transient overlay.
            onClickOutside?()
        }
        pressedHub = false
        pressStartedOutside = false
    }

    private func relativePoint(_ point: CGPoint) -> CGPoint {
        let origin = ringOrigin
        return CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    private func fire(_ index: Int) {
        guard index < bookmarks.count else { return }
        let bookmark = bookmarks[index]
        onActivate?(bookmark)
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

        // Everything below is drawn in ring space: origin at the hub centre, y down. The
        // open animation scales that whole space about the hub, so text stays centred
        // because it is measured after the transform rather than scaled afterwards.
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        let scale = 0.86 + 0.14 * CGFloat(Easing.outBack(appear, overshoot: 1.4))
        context.scaleBy(x: scale, y: scale)

        if bookmarks.isEmpty {
            drawEmptyState(alpha: content)
        } else {
            drawSlices(in: context, contentAlpha: content, pageAlpha: pageSwap.value)
        }
        drawHub(in: context, contentAlpha: content)
        drawFooter(alpha: content)

        context.restoreGState()

        if paging.pageCount > 1 {
            drawPageIndicator(in: context, center: center, alpha: content)
        }
    }

    private func drawBackdrop(in context: CGContext, center: CGPoint, alpha: Double) {
        // A soft radial scrim separates the menu from whatever is behind it without dimming
        // the whole screen, so the menu still feels like an overlay rather than a modal.
        let outer = max(menuRadius * 1.55, 260)
        let colors = [
            Theme.backdropCenter.withAlphaComponent(0.55 * alpha).cgColor,
            Theme.backdropEdge.cgColor,
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 1]
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

    private func drawSlices(in context: CGContext, contentAlpha: Double, pageAlpha: Double) {
        let ringLayout = self.ringLayout
        let count = bookmarks.count
        guard count > 0 else { return }

        let gap = min(0.018, ringLayout.step * 0.055)
        let pageSlide = CGFloat((1 - Easing.outCubic(min(1, max(0, pageAlpha)))) * 14)

        for index in 0..<count {
            guard let bookmark = bookmarks[safe: index] else { continue }
            let hover = sliceHover[safe: index]?.value ?? 0
            let press = slicePress[safe: index]?.value ?? 0

            // Hover and press widen the wedge slightly, so the target grows under the cursor.
            let expand = CGFloat(hover) * 0.004 + CGFloat(press) * 0.004
            let drawn = ringLayout.drawableRange(of: index, inset: gap - expand)
            guard drawn.sweep > 0.002 else { continue }

            let inner = ringLayout.innerRadius + 3 - CGFloat(hover) * 4
            let outer = ringLayout.outerRadius - 3 - CGFloat(press) * 5
            let path = wedgePath(start: drawn.start, sweep: drawn.sweep, inner: inner, outer: outer, layout: ringLayout)

            context.saveGState()
            context.addPath(path)
            context.clip()

            let lift = CGFloat(hover) * 10
            let gradientColors = gradientColors(for: hover)
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: gradientColors.map(\.cgColor) as CFArray,
                locations: [0, 1]
            ) {
                let anchor = ringLayout.point(radius: ringLayout.outerRadius - lift, angle: ringLayout.centerAngle(of: index))
                let innerPoint = ringLayout.point(radius: ringLayout.innerRadius, angle: ringLayout.centerAngle(of: index))
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: innerPoint.x, y: innerPoint.y),
                    end: CGPoint(x: anchor.x, y: anchor.y),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }
            context.restoreGState()

            // Border
            context.saveGState()
            context.addPath(path)
            context.setStrokeColor((hover > 0.02 ? Theme.sliceBorderHover : Theme.sliceBorder)
                .withAlphaComponent(0.30 + 0.55 * hover).cgColor)
            context.setLineWidth(1)
            context.setLineJoin(.round)
            context.strokePath()
            context.restoreGState()

            drawSliceContent(
                in: context,
                index: index,
                bookmark: bookmark,
                ringLayout: ringLayout,
                hover: hover,
                press: press,
                alpha: contentAlpha,
                slide: pageSlide
            )
        }
    }

    private func gradientColors(for hover: Double) -> [NSColor] {
        let top = blend(Theme.sliceFillTop, Theme.sliceFillHoverTop, t: hover)
        let bottom = blend(Theme.sliceFillBottom, Theme.sliceFillHoverBottom, t: hover)
        return [top, bottom]
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

    private func wedgePath(start: CGFloat, sweep: CGFloat, inner: CGFloat, outer: CGFloat,
                           layout: RadialLayout) -> CGPath {
        let path = CGMutablePath()
        let segments = max(2, Int((sweep / (.pi / 24)).rounded(.up)))
        let first = ringLayout.point(radius: outer, angle: start)
        path.move(to: first)
        for i in 1...segments {
            let t = CGFloat(i) / CGFloat(segments)
            path.addLine(to: ringLayout.point(radius: outer, angle: start + sweep * t))
        }
        for i in stride(from: segments, through: 0, by: -1) {
            let t = CGFloat(i) / CGFloat(segments)
            path.addLine(to: ringLayout.point(radius: inner, angle: start + sweep * t))
        }
        path.closeSubpath()
        return path
    }

    private func drawSliceContent(
        in context: CGContext,
        index: Int,
        bookmark: Bookmark,
        ringLayout: RadialLayout,
        hover: Double,
        press: Double,
        alpha: Double,
        slide: CGFloat
    ) {
        let angle = ringLayout.centerAngle(of: index)
        let radius = ringLayout.labelRadius + CGFloat(hover) * 6
        let anchor = ringLayout.point(radius: radius, angle: angle)
        let center = CGPoint(x: anchor.x, y: anchor.y + slide)

        // Fit the text to the wedge: at nine slices the chord is only ~80pt, and letting a
        // label be wider than its slice looks broken. Cap by both chord and radial depth.
        let chord = 2 * ringLayout.labelRadius * sin(ringLayout.step / 2)
        let depth = ringLayout.outerRadius - ringLayout.innerRadius
        let maxWidth = max(56, min(chord * 0.86, depth * 0.94))
        let titleFontSize = 12.5 * scaleFactor
        let subtitleFontSize = 10 * scaleFactor

        let titleColor = blend(Theme.titleColor, Theme.titleColorHover, t: hover)
            .withAlphaComponent((0.92 + 0.08 * hover) * alpha)
        let centredParagraph = NSMutableParagraphStyle()
        centredParagraph.alignment = .center
        centredParagraph.lineBreakMode = .byTruncatingTail
        let title = NSAttributedString(string: bookmark.displayTitle, attributes: [
            .font: Theme.titleFont(size: titleFontSize),
            .foregroundColor: titleColor,
            .paragraphStyle: centredParagraph,
        ])

        let subtitleText = bookmark.subtitle
        // Single-line labels are what makes a radial scannable: a two-line title at nine
        // slices crowds the wedge. Truncation is handled by the paragraph style.
        let titleHeight = ceil(titleFontSize * 1.38)
        let subtitleHeight: CGFloat = subtitleText.isEmpty ? 0 : ceil(subtitleFontSize * 1.4)
        let badgeHeight: CGFloat = showsNumbers ? 17 * scaleFactor : 0
        let badgeGap: CGFloat = showsNumbers ? 5 : 0
        let spacing: CGFloat = subtitleText.isEmpty ? 0 : 1
        let totalHeight = titleHeight + spacing + subtitleHeight + badgeHeight + badgeGap
        var cursorY = center.y - totalHeight / 2

        if showsNumbers {
            drawBadge(
                in: context,
                index: index,
                center: CGPoint(x: center.x, y: cursorY + badgeHeight / 2),
                hover: hover,
                alpha: alpha
            )
            cursorY += badgeHeight + badgeGap
        }

        let titleRect = CGRect(x: center.x - maxWidth / 2, y: cursorY, width: maxWidth, height: titleHeight)
        title.draw(with: titleRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        cursorY += titleHeight + spacing

        if !subtitleText.isEmpty {
            let subtitleRect = CGRect(x: center.x - maxWidth / 2, y: cursorY, width: maxWidth, height: subtitleHeight)
            let centred = NSAttributedString(string: subtitleText, attributes: [
                .font: Theme.subtitleFont(size: subtitleFontSize),
                .foregroundColor: Theme.subtitleColor.withAlphaComponent(alpha),
                .paragraphStyle: centredParagraph,
            ])
            centred.draw(with: subtitleRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }

    private func drawBadge(in context: CGContext, index: Int, center: CGPoint, hover: Double, alpha: Double) {
        let size = 17 * scaleFactor
        let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        context.saveGState()
        context.setFillColor(blend(Theme.badgeFill, Theme.badgeFillHover, t: hover).withAlphaComponent(alpha).cgColor)
        context.fillEllipse(in: rect)
        context.restoreGState()

        let label = RadialLayout.keyLabel(forSlice: index)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Theme.badgeFont(size: 10 * scaleFactor),
            .foregroundColor: Theme.badgeTextColor.withAlphaComponent(alpha),
        ]
        let string = NSAttributedString(string: label, attributes: attributes)
        let measured = string.size()
        string.draw(at: CGPoint(x: center.x - measured.width / 2, y: center.y - measured.height / 2))
    }

    private func drawHub(in context: CGContext, contentAlpha: Double) {
        let radius = hubDiameter / 2
        let hover = hubHover.value
        let press = hubPress.value
        let scale = 1 + 0.06 * hover - 0.10 * press
        let effectiveRadius = radius * scale

        context.saveGState()
        let rect = CGRect(
            x: -effectiveRadius,
            y: -effectiveRadius,
            width: effectiveRadius * 2,
            height: effectiveRadius * 2
        )
        let colors = [
            blend(Theme.hubFill, Theme.hubFillHover, t: hover).cgColor,
            blend(Theme.hubFill, Theme.hubFillHover, t: hover * 0.75).withAlphaComponent(0.92).cgColor,
        ] as CFArray
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 1]
        ) {
            context.addEllipse(in: rect)
            context.clip()
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: -effectiveRadius),
                end: CGPoint(x: 0, y: effectiveRadius),
                options: []
            )
            context.resetClip()
        }
        context.restoreGState()

        context.saveGState()
        context.setStrokeColor(Theme.hubBorder.withAlphaComponent(0.55 + 0.35 * hover).cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: CGRect(
            x: -effectiveRadius,
            y: -effectiveRadius,
            width: effectiveRadius * 2,
            height: effectiveRadius * 2
        ))
        context.restoreGState()

        drawCloseGlyph(in: context, radius: effectiveRadius, hover: hover, alpha: contentAlpha)
    }

    private func drawCloseGlyph(in context: CGContext, radius: CGFloat, hover: Double, alpha: Double) {
        // Rotation gives the X a little life when the hub is hovered.
        let rotation = CGFloat(hover) * .pi / 4
        let arm = radius * 0.30
        context.saveGState()
        context.translateBy(x: 0, y: 0)
        context.rotate(by: rotation)
        context.setStrokeColor(Theme.hubGlyph.withAlphaComponent((0.75 + 0.25 * hover) * alpha).cgColor)
        context.setLineWidth(max(1.6, radius * 0.075))
        context.setLineCap(.round)
        context.move(to: CGPoint(x: -arm, y: -arm))
        context.addLine(to: CGPoint(x: arm, y: arm))
        context.move(to: CGPoint(x: arm, y: -arm))
        context.addLine(to: CGPoint(x: -arm, y: arm))
        context.strokePath()
        context.restoreGState()
    }

    private func drawEmptyState(alpha: Double) {
        let title = NSAttributedString(string: "No bookmarks yet", attributes: [
            .font: Theme.titleFont(size: 14 * scaleFactor),
            .foregroundColor: Theme.titleColor.withAlphaComponent(alpha),
        ])
        let subtitle = NSAttributedString(string: "Add some from the menu bar icon", attributes: [
            .font: Theme.subtitleFont(size: 11 * scaleFactor),
            .foregroundColor: Theme.subtitleColor.withAlphaComponent(alpha),
        ])
        let titleSize = title.size()
        let subtitleSize = subtitle.size()
        let emptyY = max(ringLayout.innerRadius * 0.62, hubDiameter * 0.85)
        title.draw(at: CGPoint(x: -titleSize.width / 2, y: emptyY))
        subtitle.draw(at: CGPoint(
            x: -subtitleSize.width / 2,
            y: emptyY + titleSize.height + 4
        ))
    }

    private func drawFooter(alpha: Double) {
        let hint = paging.pageCount > 1
            ? "\(paging.pageSize * page + 1)–\(paging.pageSize * page + bookmarks.count) of \(paging.total)   ·   ← → page   ·   1–9 open   ·   esc closes"
            : "1–9 to open   ·   click ✕ or press the shortcut again to close"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let string = NSAttributedString(string: hint, attributes: [
            .font: NSFont.systemFont(ofSize: 10.5 * scaleFactor, weight: .medium),
            .foregroundColor: Theme.footerColor.withAlphaComponent(alpha),
            .paragraphStyle: paragraph,
        ])
        let size = string.size()
        let y = menuRadius + 44
        string.draw(with: CGRect(x: -size.width / 2 - 4, y: y, width: size.width + 8, height: size.height),
                    options: [.usesLineFragmentOrigin])
    }

    private func drawPageIndicator(in context: CGContext, center: CGPoint, alpha: Double) {
        let dotRadius: CGFloat = 2.4
        let spacing: CGFloat = 9
        let count = paging.pageCount
        let totalWidth = CGFloat(count - 1) * spacing
        let y = center.y + menuRadius + 26

        for page in 0..<count {
            let x = center.x - totalWidth / 2 + CGFloat(page) * spacing
            let isCurrent = page == self.page
            context.setFillColor((isCurrent ? NSColor.white : NSColor(white: 1, alpha: 0.30))
                .withAlphaComponent(alpha).cgColor)
            let radius = isCurrent ? dotRadius + 0.9 : dotRadius
            context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
