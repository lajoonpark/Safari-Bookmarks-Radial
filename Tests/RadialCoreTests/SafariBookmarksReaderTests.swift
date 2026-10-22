import XCTest
@testable import RadialCore

/// Real Safari files are binary plists with a nested `Children` tree. These fixtures mirror
/// the actual structure Safari writes so the parser is exercised against the real shape.
final class SafariBookmarksReaderTests: XCTestCase {

    private func makeSafariPlist(binary: Bool) throws -> Data {
        let leaf: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeLeaf",
            "URLString": "https://developer.apple.com/swift/",
            "URIDictionary": ["title": "Swift"],
        ]
        let duplicateLeaf: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeLeaf",
            "URLString": "https://developer.apple.com/swift",
            "URIDictionary": ["title": "Swift again"],
        ]
        let subfolder: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeList",
            "Title": "Frontend",
            "Children": [[
                "WebBookmarkType": "WebBookmarkTypeLeaf",
                "URLString": "https://react.dev/",
                "URIDictionary": ["title": "React"],
            ]],
        ]
        let devFolder: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeList",
            "Title": "Dev",
            "Children": [subfolder],
        ]
        // Safari wraps lists in a proxy root.
        let proxyRoot: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeProxy",
            "Title": "BookmarksBar",
            "Children": [leaf, duplicateLeaf, devFolder],
        ]
        let menu: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeList",
            "Title": "BookmarksMenu",
            "Children": [[
                "WebBookmarkType": "WebBookmarkTypeLeaf",
                "URLString": "https://news.ycombinator.com/",
                "URIDictionary": ["title": "Hacker News"],
            ]],
        ]
        // Reading list entries are also leaves; they must not pollute the menu.
        let readingList: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeList",
            "Title": "com.apple.ReadingList",
            "Children": [[
                "WebBookmarkType": "WebBookmarkTypeLeaf",
                "URLString": "https://example.com/reading",
                "URIDictionary": ["title": "Should be skipped"],
            ]],
        ]
        let root: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeList",
            "Title": "",
            "Children": [proxyRoot, menu, readingList],
        ]
        return try PropertyListSerialization.data(
            fromPropertyList: root,
            format: binary ? .binary : .xml,
            options: 0
        )
    }

    func testParsesRealSafariShape() throws {
        let bookmarks = try SafariBookmarksReader.parse(try makeSafariPlist(binary: true))
        let titles = bookmarks.map(\.title)
        XCTAssertEqual(titles, ["Swift", "React", "Hacker News"])
        XCTAssertEqual(bookmarks[0].url, "https://developer.apple.com/swift/")
    }

    func testXMLPlistAlsoParses() throws {
        let bookmarks = try SafariBookmarksReader.parse(try makeSafariPlist(binary: false))
        XCTAssertEqual(bookmarks.map(\.title), ["Swift", "React", "Hacker News"])
    }

    func testDeduplicatesByURL() throws {
        let bookmarks = try SafariBookmarksReader.parse(try makeSafariPlist(binary: true))
        let swiftEntries = bookmarks.filter { $0.url.contains("developer.apple.com") }
        XCTAssertEqual(swiftEntries.count, 1, "trailing-slash duplicate should collapse")
    }

    func testSkipsSyntheticRootsButKeepsRealFolderPaths() throws {
        let bookmarks = try SafariBookmarksReader.parse(try makeSafariPlist(binary: true))
        let react = bookmarks.first { $0.title == "React" }
        XCTAssertEqual(react?.folder, "Dev/Frontend")
        XCTAssertEqual(bookmarks.first { $0.title == "Swift" }?.folder, "")
    }

    func testSkipsReadingList() throws {
        let bookmarks = try SafariBookmarksReader.parse(try makeSafariPlist(binary: true))
        XCTAssertFalse(bookmarks.contains { $0.title == "Should be skipped" })
    }

    func testMalformedDataThrows() {
        XCTAssertThrowsError(try SafariBookmarksReader.parse(Data([0x00, 0x01, 0x02])))
    }

    func testMissingFileThrowsFileNotFound() {
        let url = URL(fileURLWithPath: "/nonexistent/Bookmarks.plist")
        XCTAssertThrowsError(try SafariBookmarksReader.read(from: url)) { error in
            guard case SafariBookmarksReader.ReadError.fileNotFound = error else {
                return XCTFail("expected fileNotFound, got \(error)")
            }
        }
    }

    func testPermissionErrorIsActionable() {
        let error = SafariBookmarksReader.ReadError.permissionDenied(URL(fileURLWithPath: "/x"))
        XCTAssertTrue(error.isPermissionProblem)
        XCTAssertTrue(error.localizedDescription.contains("Full Disk Access"))
    }

    func testIgnoresLeavesWithoutUsableURL() throws {
        let root: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeList",
            "Children": [
                ["WebBookmarkType": "WebBookmarkTypeLeaf", "URLString": "javascript:void(0)"],
                ["WebBookmarkType": "WebBookmarkTypeLeaf"],
                ["WebBookmarkType": "WebBookmarkTypeUnknownThing"],
            ],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        XCTAssertTrue(try SafariBookmarksReader.parse(data).isEmpty)
    }
}
