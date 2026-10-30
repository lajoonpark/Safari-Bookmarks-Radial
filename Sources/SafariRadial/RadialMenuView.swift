import AppKit
import Foundation
import RadialCore

/// Draws and animates the compass.
///
/// Geometry comes from `CompassMetrics`, `CompassCamera` and `RadialLayout` (all unit tested);
/// this view owns pixels, springs and input, and nothing else. Three rules keep it honest:
///
/// 1. Every animated value is a spring or an eased scalar, so nothing moves linearly.
/// 2. The aimed wedge is the only element allowed to be saturated, and it *washes* — the card
///    is paper, so aiming lights the print rather than lifting a panel.
/// 3. The lid is a real pivot, not an animation: it swings on `CompassLid`, and the pointer
///    cannot reach the card until the lid has actually cleared it.
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
    private var openProgress = SpringValue(0, stiffness: 420, damping: 27)
    /// The compass sweep that plays once as the dial appears.
    private var sweepProgress = SpringValue(0, stiffness: 300, damping: 34)
    private var sliceHover: [SpringValue] = []
    private var slicePress: [SpringValue] = []
    private var hubHover = SpringValue(0, stiffness: 380, damping: 28)
    private var hubPress = SpringValue(0, stiffness: 500, damping: 30)
    private var pageSwap = SpringValue(0, stiffness: 420, damping: 30)
    private var needle = SpringValue(0, stiffness: 300, damping: 26)
    /// Pitch and roll of the instrument, in radians, driven by where the pointer is.
    /// Springs rather than direct assignment so the compass leans with weight instead of
    /// tracking the cursor rigidly.
    private var tiltPitch = SpringValue(0, stiffness: 170, damping: 26)
    private var tiltRoll = SpringValue(0, stiffness: 170, damping: 26)
    /// How far the lid has swung.
    ///
    /// Stiff enough that the lid is half open in ~38ms and settled in ~100ms: it has to read as
    /// one flick of a sprung lid, not as an animation you watch. Still damped near critical, so
    /// it lands with a small settle rather than a wobble.
    ///
    /// Much quicker than the original tuning (210/27), which took 108ms just to reach halfway
    /// and 358ms to settle, while the case was done in ~110ms. That mismatch was the "appears,
    /// then pauses, then flips" the opening used to have: by the time the box had landed, the
    /// lid had barely moved. The kick in `present()` puts it under way on the very first frame,
    /// so there is no dead time before anything is visible.
    private var lidOpen = SpringValue(0, stiffness: 700, damping: 38)
    /// Set once the sweep has been released, so the opening beat only ever plays one time.
    private var sweepStarted = false
    /// Fired when a closing motion actually finishes, instead of after a guessed delay.
    private var closeCompletion: (() -> Void)?

    private let renderer = CompassRenderer()

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

    /// The instrument's proportions. `menuRadius` is the *card* radius, which is the one number
    /// the rest of the object is built from.
    private var metrics: CompassMetrics {
        CompassMetrics(cardRadius: menuRadius)
    }

    /// The same layout the hit test uses, so labels and clicks cannot disagree.
    private var ringLayout: RadialLayout {
        RadialLayout(
            sliceCount: max(1, bookmarks.count),
            centerRadius: metrics.hubRadius,
            outerRadius: metrics.sectorOutset
        )
    }

    /// The live tilt, from the two springs.
    private var tilt: RadialTilt {
        RadialTilt(
            pitch: CGFloat(tiltPitch.value),
            roll: CGFloat(tiltRoll.value),
            eyeDistance: menuRadius * RadialTilt.eyeDistanceRatio
        )
    }

    /// The camera, derived from the same tilt the inverse uses.
    private var camera: CompassCamera { CompassCamera(tilt: tilt) }

    private var lid: CompassLid {
        CompassLid(metrics: metrics, openness: CGFloat(lidOpen.value))
    }

    /// Whether the pointer may act on the card yet.
    ///
    /// The lid starts shut and takes ~300ms to clear. Without this gate a fast summon followed
    /// by an immediate click would fire whatever slice happened to be under the cursor while
    /// the box was still opening — the one failure mode a menu like this cannot have.
    private var cardIsReachable: Bool { lid.revealsCard }

    /// Sets the tilt the pointer asks for, and lets the springs do the rest.
    private func aimTilt(at point: CGPoint, animated: Bool) {
        // Ease in relative to the *ring* radius (wedges start where the hub ends), but use the
        // same eye distance the renderer uses, so the angle solved here produces exactly the
        // perspective the projection applies.
        let target = RadialTilt(
            leaningToward: point,
            radius: menuRadius * 1.1,
            eyeDistance: menuRadius * RadialTilt.eyeDistanceRatio
        )
        if animated {
            tiltPitch.target = Double(target.pitch)
            tiltRoll.target = Double(target.roll)
        } else {
            tiltPitch.snap(to: Double(target.pitch))
            tiltRoll.snap(to: Double(target.roll))
        }
    }

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
        sweepProgress.snap(to: 0)
        lidOpen.snap(to: 0)
        sweepStarted = false
        // Everything moves from this instant. There used to be a 0.28s timer here that held the
        // print back until the lid had cleared; because the lid spring also started from rest,
        // the visible result was the box appearing, pausing, and *then* opening. The card is
        // now revealed by the lid's own angle (`printAlpha`), so the two cannot desynchronise
        // and there is nothing to wait for.
        openProgress.target = 1
        lidOpen.target = 1
        // Both springs are kicked rather than released from rest. A spring at rest spends its
        // first frames accelerating from zero, and because the shut lid projects to very nearly
        // nothing for the first ~40° of its swing, those frames look like the box appearing and
        // then pausing before anything flips. Launching the lid already moving makes the box
        // and the lid leave together, in one gesture.
        openProgress.kick(velocity: 4.6)
        lidOpen.kick(velocity: 14)
        needle.snap(to: Double(ringLayout.centerAngle(of: 0)))
        primeHoverFromPointer()
        beginAnimating()
    }

    /// How much of the card's print is visible.
    ///
    /// Derived from the lid angle rather than from a clock, so the print can never glow through
    /// a shut lid or lag behind one that has already cleared.
    ///
    /// The window is wide on purpose. A narrow one (the first attempt spanned 0.18...0.52 of
    /// the lid's travel) put the whole reveal inside ~35ms, which reads as a flicker rather
    /// than a fade, because the lid's spring crosses that band almost instantly. Starting while
    /// the lid still hides the card costs nothing — the lid is painted over everything until it
    /// swings clear — and finishing near the lid's landing lets the print resolve with it.
    private var printProgress: Double {
        let reveal = (Double(lidOpen.value) - 0.12) / 0.74
        return min(1, max(0, reveal))
    }

    /// The dial opens under the cursor, so whatever slice is there should already be lit
    /// and the needle should already point at it.
    private func primeHoverFromPointer() {
        let point = convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
        let relative = relativePoint(point)
        aimTilt(at: relative, animated: false)
        let hit = ringLayout.hitTest(relative)
        switch hit {
        case .slice(let index) where index < bookmarks.count:
            hoveredSlice = index
            needle.snap(to: Double(ringLayout.centerAngle(of: index)))
            hubHover.snap(to: 0)
        case .close:
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
        hubHover.target = hit == .close ? 1 : 0
    }

    func dismiss(animated: Bool, completion: (() -> Void)? = nil) {
        guard !isClosing else { return }
        isClosing = true
        hoveredSlice = nil
        pressedSlice = nil
        pressedHub = false
        closeCompletion = completion
        releasePressSprings()
        if animated {
            openProgress.target = 0
            lidOpen.target = 0
            beginAnimating()
        } else {
            openProgress.snap(to: 0)
            lidOpen.snap(to: 0)
            closeCompletion = nil
            isClosing = false
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
        sweepProgress.step(dt)
        hubHover.step(dt)
        hubPress.step(dt)
        pageSwap.step(dt)
        needle.step(dt)
        tiltPitch.step(dt)
        tiltRoll.step(dt)
        lidOpen.step(dt)

        // The sweep is part of the opening gesture, not a separate beat: it fires the moment
        // the card is revealed behind the lid, so the print, the needle of light and the lid
        // landing all resolve together.
        if !sweepStarted, !isClosing, printProgress >= 0.98 {
            sweepStarted = true
            sweepProgress.target = 1
        }

        if openProgress.isAnimating || sweepProgress.isAnimating
            || hubHover.isAnimating || hubPress.isAnimating || pageSwap.isAnimating || needle.isAnimating
            || tiltPitch.isAnimating || tiltRoll.isAnimating || lidOpen.isAnimating {
            moving = true
        }

        for index in sliceHover.indices {
            sliceHover[index].step(dt)
            slicePress[index].step(dt)
            if sliceHover[index].isAnimating || slicePress[index].isAnimating { moving = true }
        }

        needsDisplay = true

        // A closing menu is finished once the compass is too small to see, not once every
        // spring has run out of its asymptote. Waiting for `isAnimating` held the panel on
        // screen for ~600ms after the lid had already shut, because a spring spends most of
        // its life in the last few percent of its travel. At 0.02 the box is a third of a
        // degree wide and the paint below it is fully transparent.
        let closedEnough = isClosing && openProgress.value <= 0.02
        if !moving || closedEnough {
            driver.stop()
            if isClosing {
                isClosing = false
                let completion = closeCompletion
                closeCompletion = nil
                completion?()
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
        // Off the menu, the disc settles back to level: holding the last lean would leave it
        // tilted toward empty space while the pointer is somewhere else entirely.
        tiltPitch.target = 0
        tiltRoll.target = 0
        applyHoverTargets()
    }

    private func handlePointer(_ point: CGPoint) {
        // Nothing on the card may react while the lid is still over it.
        guard cardIsReachable else {
            hoveredSlice = nil
            applyHoverTargets()
            return
        }
        let onScreen = relativePoint(point)
        // The pointer arrives in screen space, but the dial is drawn tilted. Unproject it
        // before hit testing, or the slice you click is not the slice under the cursor —
        // which gets worse the further from the centre you aim.
        let relative = tilt.unproject(onScreen)
        aimTilt(at: relative, animated: true)
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
        if let newHover {
            needle.target = Double(ringLayout.centerAngle(of: newHover))
        }
        hubHover.target = hit == .close ? 1 : 0
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
        let relative = tilt.unproject(relativePoint(convert(event.locationInWindow, from: nil)))
        // While the lid is still moving, a press can only dismiss: it may not fire a slice the
        // user has not seen yet. Escape is not the only way out of the opening beat.
        guard cardIsReachable else {
            pressStartedOutside = true
            return
        }
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
        let relative = tilt.unproject(relativePoint(convert(event.locationInWindow, from: nil)))
        guard cardIsReachable else {
            let escaped = pressStartedOutside && ringLayout.hitTest(relative) == .none
            pressStartedOutside = false
            if escaped { onClickOutside?() }
            return
        }
        let hit = ringLayout.hitTest(relative)

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
        let open = openProgress.value
        guard open > 0.001 else { return }

        let appear = Easing.outCubic(min(1, max(0, open)))
        let content = Easing.outCubic(printProgress)

        // The compass is a solid object, so it enters by tipping back rather than by scaling:
        // a scale from nothing looks like a sticker being placed, and a real lid has weight.
        context.saveGState()
        context.translateBy(x: ringOrigin.x, y: ringOrigin.y)
        let scale = 0.94 + 0.06 * CGFloat(appear)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -ringOrigin.x, y: -ringOrigin.y)

        if bookmarks.isEmpty {
            drawScrim(in: context, alpha: content)
            drawEmptyState(alpha: content)
        } else {
            let state = CompassRenderer.State(
                metrics: metrics,
                camera: camera,
                lid: lid,
                slices: bookmarks,
                hoveredSlice: hoveredSlice,
                hover: sliceHover.map { CGFloat(min(1, max(0, $0.value))) },
                press: slicePress.map { CGFloat(min(1, max(0, $0.value))) },
                hubHover: CGFloat(min(1, max(0, hubHover.value))),
                needleAngle: CGFloat(needle.value),
                showsNumbers: showsNumbers,
                contentAlpha: content,
                sweep: sweepProgress.value,
                pageAlpha: pageSwap.value
            )
            renderer.draw(state, in: context, at: ringOrigin)
        }

        context.restoreGState()

        if paging.pageCount > 1 {
            drawPagePips(in: context, center: ringOrigin, alpha: content)
        }
        drawHints(in: context, center: ringOrigin, alpha: content)
    }

    private func drawScrim(in context: CGContext, alpha: Double) {
        let outer = max(metrics.caseRadius * 2.9, 460)
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
            startCenter: ringOrigin,
            startRadius: 0,
            endCenter: ringOrigin,
            endRadius: outer,
            options: []
        )
    }

    private func drawEmptyState(alpha: Double) {
        let title = NSAttributedString(string: "No bookmarks yet", attributes: [
            .font: CompassTheme.serif(15 * scaleFactor, .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: CGFloat(alpha)),
        ])
        let subtitle = NSAttributedString(string: "Add one from the menu bar", attributes: [
            .font: CompassTheme.serif(10.5 * scaleFactor),
            .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: 0.72 * CGFloat(alpha)),
        ])
        let titleSize = title.size()
        let subtitleSize = subtitle.size()
        title.draw(at: CGPoint(x: ringOrigin.x - titleSize.width / 2, y: ringOrigin.y - 18))
        subtitle.draw(at: CGPoint(x: ringOrigin.x - subtitleSize.width / 2, y: ringOrigin.y + 4))
    }

    // MARK: Furniture around the instrument

    private func drawPagePips(in context: CGContext, center: CGPoint, alpha: Double) {
        let count = paging.pageCount
        let spacing: CGFloat = 15
        // Sits below the lanyard bow, so it can never land on the case.
        let y = center.y + metrics.lugReach + 22
        let totalWidth = CGFloat(count - 1) * spacing

        for page in 0..<count {
            let x = center.x - totalWidth / 2 + CGFloat(page) * spacing
            let isCurrent = page == self.page
            let string = NSAttributedString(string: "\(page + 1)", attributes: [
                .font: CompassTheme.serif(10 * scaleFactor, isCurrent ? .semibold : .regular),
                .foregroundColor: (isCurrent
                    ? CompassTheme.vermilionLit
                    : NSColor(calibratedWhite: 0.96, alpha: 0.62)
                ).withAlphaComponent(CGFloat(alpha)),
            ])
            let size = string.size()
            string.draw(at: CGPoint(x: x - size.width / 2, y: y - size.height / 2))
            if isCurrent {
                context.saveGState()
                context.setStrokeColor(CompassTheme.vermilionLit.withAlphaComponent(0.8 * CGFloat(alpha)).cgColor)
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
        // The hint names the keys that are actually live: on a three-slot dial, "1–9" promises
        // six slots that do not exist.
        let keys = bookmarks.count == 1 ? "1" : "1–\(min(bookmarks.count, RadialLayout.maxSlicesPerPage))"
        let labels: [String]
        if paging.pageCount > 1 {
            labels = ["← →", keys, "esc"]
        } else {
            labels = [keys, "esc"]
        }

        let font = CompassTheme.serif(10.5 * scaleFactor, .semibold)
        let height: CGFloat = 20
        let gap: CGFloat = 7
        let widths = labels.map { label -> CGFloat in
            max(20, (label as NSString).size(withAttributes: [.font: font]).width + 14)
        }
        let total = widths.reduce(0, +) + gap * CGFloat(labels.count - 1)
        let y = center.y + metrics.lugReach + (paging.pageCount > 1 ? 48 : 44)

        var x = center.x - total / 2
        for (index, label) in labels.enumerated() {
            let width = widths[index]
            let rect = CGRect(x: x, y: y - height / 2, width: width, height: height)
            let path = CGPath(roundedRect: rect, cornerWidth: 5, cornerHeight: 5, transform: nil)
            context.saveGState()
            context.addPath(path)
            context.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.06 * CGFloat(alpha)).cgColor)
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.16 * CGFloat(alpha)).cgColor)
            context.setLineWidth(1)
            context.strokePath()
            context.restoreGState()

            let string = NSAttributedString(string: label, attributes: [
                .font: font,
                .foregroundColor: NSColor(calibratedWhite: 0.95, alpha: 0.70 * CGFloat(alpha)),
            ])
            let size = string.size()
            string.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))

            x += width + gap
        }
    }
}
