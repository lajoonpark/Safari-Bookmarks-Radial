import AppKit
import Foundation
import RadialCore

/// Owns the radial panel's lifetime and translates model state into view state.
final class RadialController {

    private let store: BookmarkStore
    private var preferences: Preferences
    private var session: RadialSession
    private let panel = RadialPanel()
    private let menuView = RadialMenuView(frame: .zero)
    private var previouslyActiveApp: NSRunningApplication?
    /// Bumped on every presentation, so a close animation that finishes after the menu was
    /// reopened cannot tear down the new panel.
    private var presentation = 0

    /// Fired when the hotkey is pressed with nothing to show.
    var onEmptyMenu: (() -> Void)?

    init(store: BookmarkStore, preferences: Preferences) {
        self.store = store
        self.preferences = preferences
        self.session = RadialSession(paging: store.paging)

        panel.contentView = menuView
        menuView.onActivate = { [weak self] bookmark in
            self?.activate(bookmark)
        }
        menuView.onClose = { [weak self] in
            self?.dismiss()
        }
        menuView.onClickOutside = { [weak self] in
            self?.dismiss()
        }

        NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.session.isOpen, event.window === self.panel else { return event }
            return self.handleKey(event)
        }
    }

    var isOpen: Bool { session.isOpen }

    /// Settings can change while the app runs; keep the ring in sync with them.
    func updatePreferences(_ newPreferences: Preferences) {
        preferences = newPreferences
    }

    func present() {
        session.update(paging: store.paging)
        let outcome = session.toggle(hotkeyRepeated: false)
        guard case .opened(let page) = outcome else {
            if outcome == .needsMoreBookmarks { onEmptyMenu?() }
            return
        }
        show(page: page)
    }

    private func show(page: Int) {
        preferences.clamp()
        menuView.configure(
            bookmarks: store.bookmarks(onPage: page),
            page: page,
            paging: store.paging,
            showsNumbers: preferences.showNumbers,
            radius: CGFloat(preferences.menuRadius)
        )

        let screen = ScreenGeometry.activeScreen()
        let pointer = ScreenGeometry.pointerInView(screen)
        let radius = CGFloat(preferences.menuRadius)
        // Keep the whole ring plus its labels on screen, even when the cursor is in a corner.
        let margin = radius + 56
        let centerX = screen.frame.width > margin * 2
            ? min(max(pointer.x, margin), screen.frame.width - margin)
            : screen.frame.width / 2
        let centerY = screen.frame.height > margin * 2
            ? min(max(pointer.y, margin), screen.frame.height - margin)
            : screen.frame.height / 2
        let ringCenter = CGPoint(x: centerX, y: centerY)
        menuView.ringCenter = ringCenter

        // The overlay covers the whole screen so a click anywhere outside the ring dismisses it.
        let frame = CGRect(origin: screen.frame.origin, size: screen.frame.size)
        panel.setFrame(frame, display: true)
        menuView.frame = CGRect(origin: .zero, size: screen.frame.size)
        menuView.layoutSubtreeIfNeeded()

        presentation += 1
        previouslyActiveApp = NSWorkspace.shared.frontmostApplication
        // A nonactivating panel only receives key events once the app is active. Activating an
        // accessory app is invisible (no Dock icon, no menu bar), and focus is handed back on
        // dismiss, so Safari keeps its place.
        NSApp.activate(ignoringOtherApps: true)
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        menuView.present()
    }

    func dismiss() {
        guard session.isOpen else { return }
        _ = session.close()
        finishAfterClose()
    }

    private func finishAfterClose() {
        let generation = presentation
        menuView.dismiss(animated: true) { [weak self] in
            guard let self, self.presentation == generation else { return }
            self.tearDown()
        }
    }

    private func tearDown() {
        panel.orderOut(nil)
        if let app = previouslyActiveApp, app.bundleIdentifier != Bundle.main.bundleIdentifier {
            app.activate(options: [])
        }
        previouslyActiveApp = nil
    }

    /// Pointer activation goes through the session too, so both paths agree on state.
    private func activate(_ bookmark: Bookmark) {
        guard session.isOpen else { return }
        _ = session.close()
        open(bookmark)
    }

    private func open(_ bookmark: Bookmark) {
        guard let url = Bookmark.normalizedURL(bookmark.url) else { return }
        // Launch before dismissing: the click should feel like it took effect instantly.
        SafariLauncher.open(url, target: preferences.openIn, background: preferences.openInBackground)
        finishAfterClose()
    }

    private func goToPage(_ page: Int) {
        session.update(paging: store.paging)
        session.setPage(page)
        menuView.updatePage(
            bookmarks: store.bookmarks(onPage: session.page),
            page: session.page,
            paging: store.paging
        )
    }

    /// Returns nil to swallow the event, or the event to pass it on.
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 { // escape
            dismiss()
            return nil
        }
        switch event.keyCode {
        case 123: // left
            goToPage(session.paging.previousPage(from: session.page))
            return nil
        case 124: // right
            goToPage(session.paging.nextPage(from: session.page))
            return nil
        default:
            break
        }
        guard let characters = event.charactersIgnoringModifiers, let character = characters.first else {
            return event
        }
        // RadialSession owns the "which slice does this key mean" rule (and it is unit tested).
        // Anything it does not claim (⌘Q, Tab, …) must still reach the system.
        guard case .activated(let bookmark, _) = session.activate(key: character, bookmarks: store.bookmarks) else {
            return event
        }
        open(bookmark)
        return nil
    }

    /// The hotkey fired while the menu is already open.
    func hotkeyWhileOpen() {
        dismiss()
    }
}
