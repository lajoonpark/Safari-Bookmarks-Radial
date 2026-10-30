import Foundation

/// The AppleScript for the three things the launcher needs from a browser: list its tabs,
/// select one, and open a new one.
///
/// Safari and the Chromium family need different verbs for the same intent ("current tab" vs
/// "active tab index"), so each script is built from the browser's engine rather than assuming
/// one dialect. These are plain strings so they can be tested and compile-checked without a
/// browser running; every function returns `nil` for a browser that cannot be scripted.
public enum BrowserScripts {

    /// One line per open tab, `windowID<TAB>tabIndex<TAB>url`, frontmost window first.
    public static func listTabs(in browser: Browser) -> String? {
        guard let application = scriptableName(browser) else { return nil }
        return """
        set report to ""
        tell application "\(application)"
            repeat with w in windows
                set windowID to id of w
                set urls to URL of every tab of w
                repeat with i from 1 to count of urls
                    set u to item i of urls
                    if u is not missing value then
                        set report to report & windowID & (character id 9) & i & (character id 9) & u & linefeed
                    end if
                end repeat
            end repeat
        end tell
        return report
        """
    }

    /// Reads the output of `listTabs`, skipping any line that is not a tab.
    public static func parseTabs(_ output: String) -> [TabMatcher.Tab] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3, let window = Int(fields[0]), let index = Int(fields[1]) else { return nil }
            return TabMatcher.Tab(windowID: window, index: index, url: String(fields[2]))
        }
    }

    /// Brings an open tab to the front: selects it, raises its window and activates the browser.
    public static func select(_ tab: TabMatcher.Tab, in browser: Browser) -> String? {
        guard let application = scriptableName(browser) else { return nil }
        let selection: String
        switch browser.engine {
        case .safari:
            selection = """
                set miniaturized of w to false
                set current tab of w to tab \(tab.index) of w
            """
        case .chromium:
            selection = "    set active tab index of w to \(tab.index)"
        case .launchServices:
            return nil
        }
        return """
        tell application "\(application)"
            set w to window id \(tab.windowID)
        \(selection)
            set index of w to 1
            activate
        end tell
        """
    }

    /// A brand-new tab, switched to or left behind the current one.
    ///
    /// With no window open there is nothing to add a tab to, so it opens a window instead.
    public static func openNewTab(url: String, foreground: Bool, in browser: Browser) -> String? {
        guard let application = scriptableName(browser) else { return nil }
        let target = escape(url)
        let body: String
        switch browser.engine {
        case .safari: body = safariNewTab(target, foreground: foreground)
        case .chromium: body = chromiumNewTab(target, foreground: foreground)
        case .launchServices: return nil
        }
        return """
        tell application "\(application)"
            if (count of windows) is 0 then
                make new document with properties {URL:"\(target)"}
            else
                \(body)
            end if
            \(foreground ? "activate" : "")
        end tell
        """
    }

    /// Safari's `make new tab` does not select the tab it makes, so switching is explicit.
    private static func safariNewTab(_ target: String, foreground: Bool) -> String {
        let make = "make new tab at end of tabs with properties {URL:\"\(target)\"}"
        return foreground
            ? "tell front window to set current tab to (\(make))"
            : "tell front window to \(make)"
    }

    /// Chromium's `make new tab` *does* select the new tab, so staying put means recording the
    /// previous tab and putting it back.
    private static func chromiumNewTab(_ target: String, foreground: Bool) -> String {
        let make = "make new tab at end of tabs with properties {URL:\"\(target)\"}"
        guard !foreground else { return "tell front window to \(make)" }
        return """
        tell front window
                set previousTabIndex to active tab index
                \(make)
                set active tab index to previousTabIndex
            end tell
        """
    }

    private static func scriptableName(_ browser: Browser) -> String? {
        browser.engine == .launchServices ? nil : browser.scriptName
    }

    static func escape(_ string: String) -> String {
        string.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
