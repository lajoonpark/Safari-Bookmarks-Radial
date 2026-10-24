import AppKit
import RadialCore

/// Opens bookmarks in the browser the user chose.
///
/// The interesting case is `New tab`. Handing a URL to `NSWorkspace` with a target
/// application *looks* like opening a tab, but Safari and the Chromium family both treat it
/// as "open this address", which re-focuses an existing tab when that link is already loaded
/// — so the user's "New tab" setting quietly meant "new tab, unless I already had it open".
/// The only way to force a literal new tab is to ask the browser, which is why a scriptable
/// browser gets an AppleScript and an unscriptable one gets the plain open plus an honest
/// note in Settings.
enum BrowserLauncher {

    static func open(
        _ url: URL,
        target: Preferences.OpenTarget,
        browser: Browser,
        background: Bool
    ) {
        let plan = OpenPlan.resolve(target: target, in: browser)
        guard case .scripted(let action) = plan,
              let applicationName = browser.scriptName,
              browser.engine != .launchServices
        else {
            openViaLaunchServices(url, browser: browser, background: background)
            return
        }
        let source = script(
            for: action,
            url: url,
            browser: browser,
            application: applicationName,
            background: background
        )
        if !runAppleScript(source) {
            // Consent denied, or the browser is busy. A plain open still gets the page in
            // front of the user; it may just land in a tab that already had it.
            openViaLaunchServices(url, browser: browser, background: background)
        }
    }

    /// `withApplicationAt:` targets one specific browser and needs no scripting at all.
    static func openViaLaunchServices(_ url: URL, browser: Browser, background: Bool) {
        guard let applicationURL = applicationURL(for: browser) else {
            NSWorkspace.shared.open(url)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = !background
        NSWorkspace.shared.open([url], withApplicationAt: applicationURL, configuration: configuration) { _, error in
            if let error {
                NSLog("SafariRadial: failed to open \(url.absoluteString): \(error.localizedDescription)")
                DispatchQueue.main.async { NSWorkspace.shared.open(url) }
            }
        }
    }

    static func applicationURL(for browser: Browser) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID)
    }

    static func isInstalled(_ browser: Browser) -> Bool {
        applicationURL(for: browser) != nil
    }

    /// Browsers on this Mac, always including the selected one.
    static func installedBrowsers(selected: Browser) -> [Browser] {
        BrowserCatalog.available(selected: selected) { isInstalled(Browser.browser(forBundleID: $0)) }
    }

    // MARK: - Scripts

    /// Safari and the Chromium family need different verbs for the same intent, so the
    /// script is built from the browser's engine rather than assuming one dialect.
    private static func script(
        for action: OpenPlan.ScriptedAction,
        url: URL,
        browser: Browser,
        application: String,
        background: Bool
    ) -> String {
        let target = escape(url.absoluteString)
        let activate = background ? "" : "activate"
        let newTab: String
        switch action {
        case .currentTab:
            newTab = "set URL of current tab of front window to \"\(target)\""
        case .newWindow:
            newTab = "make new document with properties {URL:\"\(target)\"}"
        case .newTab:
            switch browser.engine {
            case .chromium: newTab = chromiumNewTabBody(target, background: background)
            case .safari, .launchServices: newTab = safariNewTabBody(target)
            }
        }
        return """
        tell application "\(application)"
            if (count of windows) is 0 then
                make new document with properties {URL:"\(target)"}
            else
                \(newTab)
            end if
            \(activate)
        end tell
        """
    }

    /// Safari's `make new tab` inserts at the end without stealing focus, so background
    /// opening needs no bookkeeping here.
    private static func safariNewTabBody(_ target: String) -> String {
        "tell front window to make new tab at end of tabs with properties {URL:\"\(target)\"}"
    }

    /// Chromium's `make new tab` *does* select the new tab, so keeping the previous tab
    /// focused means recording its index and putting it back.
    private static func chromiumNewTabBody(_ target: String, background: Bool) -> String {
        let restore = background ? "\n            set active tab index of front window to previousTabIndex" : ""
        return """
        tell front window
                set previousTabIndex to active tab index
                make new tab at end of tabs with properties {URL:"\(target)"}\(restore)
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
