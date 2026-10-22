import AppKit
import RadialCore

/// Opens bookmarks in Safari.
///
/// The common path (new tab) uses `NSWorkspace`, which needs no automation consent.
/// Targeting the current tab or a new window needs AppleScript, so those fall back to a
/// new tab when the user has not approved automation access.
enum SafariLauncher {

    static func open(_ url: URL, target: Preferences.OpenTarget, background: Bool) {
        switch target {
        case .newTab:
            openNewTab(url, background: background)
        case .currentTab:
            if !runAppleScript(loadInCurrentTabScript(url)) {
                openNewTab(url, background: background)
            }
        case .newWindow:
            if !runAppleScript(newWindowScript(url)) {
                openNewTab(url, background: background)
            }
        }
    }

    /// `withApplicationAt:` always opens a tab in the chosen browser, and works without
    /// any TCC permission prompts.
    static func openNewTab(_ url: URL, background: Bool) {
        guard let safari = safariURL else {
            NSWorkspace.shared.open(url)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = !background
        NSWorkspace.shared.open([url], withApplicationAt: safari, configuration: configuration) { _, error in
            if let error {
                NSLog("SafariRadial: failed to open \(url.absoluteString): \(error.localizedDescription)")
                DispatchQueue.main.async { NSWorkspace.shared.open(url) }
            }
        }
    }

    static var safariURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")
    }

    static var isSafariInstalled: Bool { safariURL != nil }

    /// Shows Safari's bookmark editor, for the "Safari side" of bookmark management.
    static func revealSafariBookmarks() {
        guard let safari = safariURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let script = """
        tell application "Safari" to activate
        tell application "System Events" to tell process "Safari" to keystroke "b" using {command down, option down}
        """
        if !runAppleScript(script) {
            NSWorkspace.shared.openApplication(at: safari, configuration: configuration)
        }
    }

    // MARK: - AppleScript

    private static func loadInCurrentTabScript(_ url: URL) -> String {
        """
        tell application "Safari"
            activate
            if (count of windows) is 0 then
                make new document with properties {URL:"\(escape(url.absoluteString))"}
            else
                set URL of current tab of front window to "\(escape(url.absoluteString))"
            end if
        end tell
        """
    }

    private static func newWindowScript(_ url: URL) -> String {
        """
        tell application "Safari"
            activate
            make new document with properties {URL:"\(escape(url.absoluteString))"}
        end tell
        """
    }

    private static func escape(_ string: String) -> String {
        string.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    @discardableResult
    static func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        script.executeAndReturnError(&error)
        if let error {
            NSLog("SafariRadial: AppleScript failed: \(error)")
            return false
        }
        return true
    }
}
