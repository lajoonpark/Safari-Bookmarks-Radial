import Foundation

/// Turns "open this link, that way, in that browser" into something a launcher can act on.
///
/// This exists as a value type because the interesting part is *not* AppleScript: it is the
/// rule that a behaviour is either kept exactly or admitted as approximated. Handing a URL to
/// `NSWorkspace` looks like it opens a tab, but Safari and Chrome both treat it as "open this
/// address", which re-focuses an existing tab when the link is already loaded — so "New tab"
/// silently meant "new tab, or whatever tab already had it".
///
/// The rule: when the browser can be scripted, do exactly what was asked. When it cannot, fall
/// back to a plain open, and say so in the description so the UI does not promise more.
public enum OpenPlan: Equatable, Sendable {
    /// Hand the URL to Launch Services with no scripting. The browser picks the tab.
    case launchServices(background: Bool)
    /// Drive the browser's tabs directly.
    case scripted(OpenBehavior, matchWholeSite: Bool)

    public static func resolve(
        behavior: OpenBehavior,
        matchWholeSite: Bool = false,
        in browser: Browser
    ) -> OpenPlan {
        guard browser.canForceNewTab else {
            return .launchServices(background: !behavior.switchesToLink)
        }
        return .scripted(behavior, matchWholeSite: matchWholeSite)
    }

    /// The plan for one bookmark: its own behaviour if it has one, otherwise the default.
    public static func resolve(
        _ bookmark: Bookmark,
        default fallback: OpenBehavior,
        in browser: Browser
    ) -> OpenPlan {
        resolve(
            behavior: bookmark.effectiveOpenBehavior(default: fallback),
            matchWholeSite: bookmark.matchesWholeSite,
            in: browser
        )
    }

    /// Whether a browser can be told what to do with its tabs, or only handed the link.
    ///
    /// Firefox and Arc have no tab scripting, so none of the three behaviours can be forced
    /// there. Saying so is better than letting a setting quietly do nothing.
    public static func honours(_ browser: Browser) -> Bool { browser.canForceNewTab }

    /// How a behaviour is described for a given browser, e.g. "Go to open tab in Safari".
    public static func description(for behavior: OpenBehavior, in browser: Browser) -> String {
        guard honours(browser) else {
            return "\(browser.name) decides which tab a link opens in"
        }
        return "\(behavior.displayName) in \(browser.name)"
    }
}

/// Decides whether one of the browser's open tabs already has a bookmark.
///
/// Kept apart from the AppleScript that lists the tabs so the rule can be tested: the script
/// only reports what is open, and everything about what counts as "the same" is here.
public enum TabMatcher {

    public struct Tab: Equatable, Sendable {
        public var windowID: Int
        /// 1-based, as the browsers number tabs.
        public var index: Int
        public var url: String

        public init(windowID: Int, index: Int, url: String) {
            self.windowID = windowID
            self.index = index
            self.url = url
        }
    }

    /// The first tab that already has `url`, searching in the order given (frontmost window
    /// first). With `wholeSite`, an exact page still wins over any other tab on the same site.
    public static func firstMatch(in tabs: [Tab], for url: String, wholeSite: Bool) -> Tab? {
        let page = pageKey(url)
        if let exact = tabs.first(where: { pageKey($0.url) == page }) { return exact }
        guard wholeSite, let site = siteKey(url) else { return nil }
        return tabs.first { siteKey($0.url) == site }
    }

    /// The page a URL names, ignoring what does not change which page it is: `www.`, the
    /// scheme, a `#fragment` and trailing slashes.
    static func pageKey(_ url: String) -> String {
        guard let parts = components(url), let host = parts.host else {
            return url.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var path = parts.path
        while path.hasSuffix("/") { path.removeLast() }
        let query = parts.query.map { "?\($0)" } ?? ""
        return stripWWW(host.lowercased()) + path + query
    }

    static func siteKey(_ url: String) -> String? {
        components(url)?.host.map { stripWWW($0.lowercased()) }
    }

    private static func components(_ url: String) -> URLComponents? {
        URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func stripWWW(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
