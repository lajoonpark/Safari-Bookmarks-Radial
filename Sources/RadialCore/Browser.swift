import Foundation

/// A browser this app can send links to.
///
/// "Open in the browser you actually use" is the whole point, so the list is a catalogue of
/// bundle identifiers rather than a free-text field: an identifier is what `NSWorkspace` and
/// AppleScript both need, and a typo in one would fail silently at the worst moment.
public struct Browser: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let bundleID: String
    public let name: String
    /// AppleScript application name, for the engines that can be told to make a new tab.
    /// `nil` means "no scripting support", and the launcher falls back to `NSWorkspace`.
    public let scriptName: String?
    public let engine: Engine

    /// How a browser exposes tabs. The two scriptable families disagree on almost every
    /// verb ("current tab" vs "active tab"), so the dialect is a property of the browser
    /// rather than something the launcher guesses.
    public enum Engine: String, Codable, Sendable {
        /// `current tab of front window`, `make new tab at end of tabs`.
        case safari
        /// `active tab index`, and `make new tab` *selects* the tab it creates.
        case chromium
        /// No usable tab scripting: only Launch Services, so a new tab cannot be forced.
        case launchServices
    }

    public var id: String { bundleID }

    /// Whether this browser can be asked for a literal new tab.
    public var canForceNewTab: Bool { scriptName != nil && engine != .launchServices }

    public init(
        bundleID: String,
        name: String,
        scriptName: String? = nil,
        engine: Engine = .launchServices
    ) {
        self.bundleID = bundleID
        self.name = name
        self.scriptName = scriptName
        self.engine = engine
    }

    public static let safari = Browser(
        bundleID: "com.apple.Safari",
        name: "Safari",
        scriptName: "Safari",
        engine: .safari
    )

    public static let chrome = Browser(
        bundleID: "com.google.Chrome",
        name: "Google Chrome",
        scriptName: "Google Chrome",
        engine: .chromium
    )

    public static let chromium = Browser(
        bundleID: "org.chromium.Chromium",
        name: "Chromium",
        scriptName: "Chromium",
        engine: .chromium
    )

    public static let edge = Browser(
        bundleID: "com.microsoft.edgemac",
        name: "Microsoft Edge",
        scriptName: "Microsoft Edge",
        engine: .chromium
    )

    public static let brave = Browser(
        bundleID: "com.brave.Browser",
        name: "Brave",
        scriptName: "Brave Browser",
        engine: .chromium
    )

    /// Arc has no tab dictionary; asking it for a new tab fails, so it is offered as a
    /// plain target rather than pretending the tab options work.
    public static let arc = Browser(
        bundleID: "company.thebrowser.Browser",
        name: "Arc"
    )

    public static let vivaldi = Browser(
        bundleID: "com.vivaldi.Vivaldi",
        name: "Vivaldi",
        scriptName: "Vivaldi",
        engine: .chromium
    )

    public static let opera = Browser(
        bundleID: "com.operasoftware.Opera",
        name: "Opera",
        scriptName: "Opera",
        engine: .chromium
    )

    public static let firefox = Browser(
        bundleID: "org.mozilla.firefox",
        name: "Firefox"
    )

    /// Every browser the app offers, in a deliberate order: the system default first, then
    /// the ones people actually switch to.
    public static let catalogue: [Browser] = [
        .safari, .chrome, .arc, .brave, .edge, .vivaldi, .opera, .chromium, .firefox,
    ]

    public static func browser(forBundleID id: String?) -> Browser {
        guard let id else { return .safari }
        return catalogue.first { $0.bundleID == id } ?? .safari
    }
}

/// Which browsers are actually on this Mac, without importing AppKit into the core.
///
/// The lookup is injected so the catalogue logic stays testable; the app passes
/// `NSWorkspace`-backed resolution, tests pass a stub.
public enum BrowserCatalog {
    /// Browsers that are installed, plus the selected one even if it is not found (so a
    /// browser that is temporarily unavailable — an external volume, a rename — does not
    /// delete the user's choice from the picker).
    public static func available(
        selected: Browser,
        isInstalled: (String) -> Bool
    ) -> [Browser] {
        var result = Browser.catalogue.filter { isInstalled($0.bundleID) }
        if !result.contains(selected) {
            result.insert(selected, at: 0)
        }
        return result
    }
}
