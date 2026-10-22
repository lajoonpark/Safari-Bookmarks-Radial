import Foundation

/// A single bookmark shown in the radial menu.
public struct Bookmark: Codable, Equatable, Identifiable, Hashable {
    public var id: UUID
    public var title: String
    public var url: String
    /// Human readable folder path from Safari, e.g. "Dev/Swift". Empty for top level.
    public var folder: String

    public init(id: UUID = UUID(), title: String, url: String, folder: String = "") {
        self.id = id
        self.title = title
        self.url = url
        self.folder = folder
    }

    public var host: String {
        URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? ""
    }

    /// Falls back to the host so a slice is never blank.
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return host.isEmpty ? url : host
    }

    /// Second line of a slice. Prefers the folder, otherwise the host. Hidden when it would
    /// just restate the title, which keeps slices short enough to scan at a glance.
    public var subtitle: String {
        let folder = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        if !folder.isEmpty { return folder }
        let host = host
        guard !host.isEmpty else { return "" }
        let titleKey = Bookmark.looseKey(displayTitle)
        let hostKey = Bookmark.looseKey(host)
        // "GitHub" vs "github.com", or "github.com/x" vs "github.com" — not worth two lines.
        if !titleKey.isEmpty, hostKey.hasPrefix(titleKey) || titleKey.hasPrefix(hostKey) { return "" }
        return host
    }

    /// Lowercased alphanumerics only, so "GitHub" and "github.com" compare meaningfully.
    static func looseKey(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Normalises user input into an openable web URL.
    /// Bare hosts get `https://`, anything that is not http(s) is rejected
    /// (bookmarklets, file URLs and mail links cannot be opened in a tab).
    public static func normalizedURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") && !text.lowercased().hasPrefix("mailto:") {
            text = "https://" + text
        }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    /// Key used to spot the same link twice (import dedupe, store merging).
    public var comparisonKey: String {
        var key = url.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        while key.hasSuffix("/") { key.removeLast() }
        return key
    }
}
