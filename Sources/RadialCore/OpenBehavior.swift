import Foundation

/// What opening a link does to the tabs you already have.
///
/// There are three, and they are the whole vocabulary: it is the same one Settings offers as
/// the default and the edit sheet offers per bookmark, so a link never opens in a way the
/// default cannot also describe.
public enum OpenBehavior: String, Codable, CaseIterable, Sendable {
    /// Select a tab that already has the link. Opens a new tab and switches to it when none does.
    case reuseTab
    /// A new tab behind the one you are on, which stays in front.
    case newTabBackground
    /// A new tab, switched to.
    case newTabForeground

    public var displayName: String {
        switch self {
        case .reuseTab: return "Go to open tab"
        case .newTabBackground: return "New tab, stay here"
        case .newTabForeground: return "New tab, switch to it"
        }
    }

    /// One line for the place that has room to explain it.
    public var summary: String {
        switch self {
        case .reuseTab: return "Jumps to a tab that already has it, or opens one."
        case .newTabBackground: return "Opens a new tab behind the one you are on."
        case .newTabForeground: return "Opens a new tab and switches to it."
        }
    }

    /// Whether the browser ends up in front, showing the link.
    public var switchesToLink: Bool { self != .newTabBackground }

    /// Carries the two settings this replaced forward without changing anyone's behaviour.
    ///
    /// `New tab` keeps its background flag. `Current tab` and `New window` no longer exist,
    /// and a new tab you switch to is the nearest of the three to both.
    static func migrating(legacyTarget: String?, background: Bool) -> OpenBehavior {
        guard legacyTarget == nil || legacyTarget == "newTab" else { return .newTabForeground }
        return background ? .newTabBackground : .newTabForeground
    }
}

extension Bookmark {
    /// The behaviour this link opens with, given the default from Settings.
    public func effectiveOpenBehavior(default fallback: OpenBehavior) -> OpenBehavior {
        openBehavior ?? fallback
    }

    /// Whether a tab on the same site, not just the same page, counts as this link being open.
    public var matchesWholeSite: Bool { matchWholeSite ?? false }
}
