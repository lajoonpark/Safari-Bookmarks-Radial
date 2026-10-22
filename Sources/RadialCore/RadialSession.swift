import Foundation

/// The interaction state machine behind the radial menu.
///
/// It is deliberately free of AppKit so that every rule the user feels — which slice a
/// keystroke fires, what happens on a repeated hotkey, how paging wraps — is testable.
public final class RadialSession {

    public enum Outcome: Equatable {
        case none
        /// The menu should open (or stay open) on the given page.
        case opened(page: Int)
        case closed
        case activated(bookmark: Bookmark, index: Int)
        case pageChanged(page: Int)
        case needsMoreBookmarks
    }

    public private(set) var isOpen = false
    public private(set) var page = 0
    public var paging: RadialPaging

    public init(paging: RadialPaging = RadialPaging(total: 0)) {
        self.paging = paging
    }

    public func update(paging: RadialPaging) {
        self.paging = paging
        page = paging.clampedPage(page)
    }

    /// Pressing the shortcut: opens when closed, closes when already open.
    @discardableResult
    public func toggle(hotkeyRepeated: Bool) -> Outcome {
        if isOpen {
            isOpen = false
            return .closed
        }
        guard paging.total > 0 else { return .needsMoreBookmarks }
        page = paging.clampedPage(page)
        isOpen = true
        return .opened(page: page)
    }

    @discardableResult
    public func close() -> Outcome {
        guard isOpen else { return .none }
        isOpen = false
        return .closed
    }

    /// Number key 1…9 is a direct hit on the slice of the current page.
    public func activate(key character: Character, bookmarks: [Bookmark]) -> Outcome {
        guard isOpen, let idx = RadialLayout.sliceIndex(forKey: character) else { return .none }
        let indices = paging.items(onPage: page)
        guard idx < indices.count else { return .none }
        let bookmark = bookmarks[indices[idx]]
        isOpen = false
        return .activated(bookmark: bookmark, index: indices[idx])
    }

    public func activate(slice index: Int, bookmarks: [Bookmark]) -> Outcome {
        guard isOpen else { return .none }
        let indices = paging.items(onPage: page)
        guard index >= 0, index < indices.count else { return .none }
        let bookmark = bookmarks[indices[index]]
        isOpen = false
        return .activated(bookmark: bookmark, index: indices[index])
    }

    /// Jumps to a page directly (arrow keys that wrap, or an explicit page request).
    @discardableResult
    public func setPage(_ newPage: Int) -> Outcome {
        guard isOpen else { return .none }
        let clamped = paging.clampedPage(newPage)
        guard clamped != page else { return .none }
        page = clamped
        return .pageChanged(page: page)
    }

    public func nextPage() -> Outcome {
        guard isOpen, paging.pageCount > 1 else { return .none }
        page = paging.nextPage(from: page)
        return .pageChanged(page: page)
    }

    public func previousPage() -> Outcome {
        guard isOpen, paging.pageCount > 1 else { return .none }
        page = paging.previousPage(from: page)
        return .pageChanged(page: page)
    }

    /// Escape drops out of the menu without opening anything.
    public func cancel() -> Outcome { close() }
}
