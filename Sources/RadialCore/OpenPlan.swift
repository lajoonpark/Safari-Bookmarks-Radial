import Foundation

/// Turns "open this link, that way, in that browser" into something a launcher can act on.
///
/// This exists as a value type because the interesting part is *not* AppleScript: it is the
/// rule that `New tab` really means a new tab. Handing a URL to `NSWorkspace` with a target
/// application looks like it opens a tab, but Safari and Chrome both treat it as "open this
/// address", which re-focuses an existing tab when the link is already loaded somewhere —
/// so the setting silently meant "New tab, or whatever tab already had it".
///
/// The rule: when the browser can be scripted, ask it for a literal new tab and nothing
/// else. When it cannot, fall back to a plain open, and say so in the resulting plan so the
/// UI does not promise something it cannot deliver.
public enum OpenPlan: Equatable, Sendable {
    /// Hand the URL to Launch Services with no scripting. May reuse an existing tab.
    case launchServices
    /// Ask the browser for a brand-new tab/window.
    case scripted(ScriptedAction)

    public enum ScriptedAction: Equatable, Sendable {
        case newTab
        case currentTab
        case newWindow
    }

    /// What the app will actually do, given the requested target and the browser's powers.
    public static func resolve(target: Preferences.OpenTarget, in browser: Browser) -> OpenPlan {
        guard browser.canForceNewTab else {
            // Firefox, or anything else without a tab API: a new tab is the only honest
            // promise, and Launch Services is the only way to ask for it.
            return .launchServices
        }
        switch target {
        case .newTab: return .scripted(.newTab)
        case .currentTab: return .scripted(.currentTab)
        case .newWindow: return .scripted(.newWindow)
        }
    }

    /// Whether the requested target is honoured exactly, or approximated.
    ///
    /// `Current tab` and `New window` are impossible without scripting, so on an unscriptable
    /// browser they degrade to a plain open. Settings uses this to word the picker honestly.
    public static func honoursTarget(_ target: Preferences.OpenTarget, in browser: Browser) -> Bool {
        browser.canForceNewTab || target == .newTab
    }

    /// How a target is described for a given browser, e.g. "New window in Safari".
    public static func description(for target: Preferences.OpenTarget, in browser: Browser) -> String {
        guard honoursTarget(target, in: browser) else {
            return "\(target.displayName) — opens in a new tab in \(browser.name)"
        }
        return "\(target.displayName) in \(browser.name)"
    }
}
