import Foundation

/// Pure geometry for the radial menu. No AppKit, so it can be unit tested on any platform.
///
/// Angles are measured **clockwise from 12 o'clock**, which is how the slices are laid out
/// on screen. Points passed to `hitTest` are relative to the centre of the ring with
/// **y pointing down** (screen coordinates), matching `NSView(isFlipped: true)`.
public struct RadialLayout: Equatable {
    public static let maxSlicesPerPage = 9

    public let sliceCount: Int
    /// Radius of the close button in the middle.
    public let centerRadius: CGFloat
    /// Where a slice starts; the hub gap is slightly larger than the close button so the
    /// two targets never overlap.
    public let innerRadius: CGFloat
    public let outerRadius: CGFloat

    public init(sliceCount: Int, centerRadius: CGFloat = 52, outerRadius: CGFloat = 200) {
        self.sliceCount = max(0, sliceCount)
        self.centerRadius = centerRadius
        self.innerRadius = centerRadius * 1.16
        self.outerRadius = max(outerRadius, self.innerRadius + 40)
    }

    public var step: CGFloat {
        guard sliceCount > 0 else { return 0 }
        return (2 * .pi) / CGFloat(sliceCount)
    }

    /// Angle of the centre line of slice `index`.
    public func centerAngle(of index: Int) -> CGFloat {
        CGFloat(index) * step
    }

    /// Start/end angles of slice `index`, both in `[0, 2π)`.
    public func angleRange(of index: Int) -> (start: CGFloat, end: CGFloat) {
        let start = centerAngle(of: index) - step / 2
        return (RadialLayout.normalize(start), RadialLayout.normalize(start + step))
    }

    /// The part of slice `index` that should actually be painted.
    ///
    /// `angleRange` wraps at 12 o'clock, so slice 0 comes back as start ≈ 2π − step/2 with a
    /// smaller end. Callers that compare `end > start` silently drop that slice, so the
    /// inset-and-wrap maths lives here, where it can be tested.
    public func drawableRange(of index: Int, inset: CGFloat) -> (start: CGFloat, sweep: CGFloat) {
        guard sliceCount > 0 else { return (0, 0) }
        // A lone slice is a full ring: no seam, and no gap to inset for a neighbour.
        if sliceCount == 1 { return (0, 2 * .pi) }
        let range = angleRange(of: index)
        let sweep = RadialLayout.normalize(range.end - range.start)
        let clampedInset = min(max(0, inset), max(0, sweep / 2 - 0.001))
        return (RadialLayout.normalize(range.start + clampedInset), sweep - clampedInset * 2)
    }

    public enum Hit: Equatable {
        case close
        case slice(Int)
        case none
    }

    /// Resolves a point to a target. Outside `outerRadius` counts as `.none` so that
    /// flicking away from the menu is a deliberate miss rather than a random pick.
    public func hitTest(_ point: CGPoint) -> Hit {
        let radius = hypot(point.x, point.y)
        if radius <= centerRadius { return .close }
        guard radius <= outerRadius, sliceCount > 0 else { return .none }
        return .slice(sliceIndex(for: point))
    }

    /// Slice under `point`, ignoring the radial distance. Used for hover while the
    /// pointer sits in the hub gap.
    public func sliceIndex(for point: CGPoint) -> Int {
        guard sliceCount > 0 else { return 0 }
        let theta = RadialLayout.normalize(atan2(point.x, -point.y))
        let raw = (theta / step).rounded()
        let index = Int(raw) % sliceCount
        return index < 0 ? index + sliceCount : index
    }

    /// Clockwise angle in `[0, 2π)` measured from straight up.
    public static func normalize(_ angle: CGFloat) -> CGFloat {
        let twoPi = 2 * CGFloat.pi
        var value = angle.truncatingRemainder(dividingBy: twoPi)
        if value < 0 { value += twoPi }
        return value
    }

    /// Outline of a slice, used for both drawing and hover geometry.
    public func path(from start: CGFloat, to end: CGFloat) -> [CGPoint] {
        var points: [CGPoint] = []
        let sweep = RadialLayout.normalize(end - start)
        let segments = max(2, Int((sweep / (.pi / 24)).rounded(.up)))
        for i in 0...segments {
            let t = CGFloat(i) / CGFloat(segments)
            points.append(point(radius: outerRadius, angle: start + sweep * t))
        }
        for i in stride(from: segments, through: 0, by: -1) {
            let t = CGFloat(i) / CGFloat(segments)
            points.append(point(radius: innerRadius, angle: start + sweep * t))
        }
        return points
    }

    public func point(radius: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(x: radius * sin(angle), y: -radius * cos(angle))
    }

    /// Anchor for a slice's label, in the middle of the wedge.
    public func labelPoint(for index: Int) -> CGPoint {
        point(radius: labelRadius, angle: centerAngle(of: index))
    }

    public var labelRadius: CGFloat { innerRadius + (outerRadius - innerRadius) * 0.44 }

    /// Keyboard shortcut shown inside slice `index` (1…9 within the current page).
    public static func keyLabel(forSlice index: Int) -> String {
        String(index + 1)
    }

    /// Maps a typed character to a slice index on the current page.
    public static func sliceIndex(forKey character: Character) -> Int? {
        guard let value = character.wholeNumberValue, (1...maxSlicesPerPage).contains(value) else {
            return nil
        }
        return value - 1
    }
}

/// Splits an ordered bookmark list into pages of at most `maxSlicesPerPage`.
public struct RadialPaging: Equatable {
    public let total: Int
    public let pageSize: Int

    public init(total: Int, pageSize: Int = RadialLayout.maxSlicesPerPage) {
        self.total = max(0, total)
        self.pageSize = max(1, pageSize)
    }

    public var pageCount: Int { max(1, Int(ceil(Double(total) / Double(pageSize)))) }

    public func indices(onPage page: Int) -> Range<Int> {
        let start = clampedPage(page) * pageSize
        return start..<min(start + pageSize, total)
    }

    public func items(onPage page: Int) -> [Int] { Array(indices(onPage: page)) }

    public func sliceCount(onPage page: Int) -> Int { indices(onPage: page).count }

    public func clampedPage(_ page: Int) -> Int { min(max(0, page), pageCount - 1) }

    public func nextPage(from page: Int) -> Int { (clampedPage(page) + 1) % pageCount }

    public func previousPage(from page: Int) -> Int {
        (clampedPage(page) - 1 + pageCount) % pageCount
    }
}
