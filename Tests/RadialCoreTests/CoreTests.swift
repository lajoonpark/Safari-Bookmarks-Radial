import XCTest
// Same override as the core target: an optimized (`swift test -c release`) test module that
// constructs CGPoint without the overlay re-triggers swiftlang/swift#92222.
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import RadialCore

final class RadialLayoutTests: XCTestCase {

    func testSliceZeroIsStraightUp() {
        let layout = RadialLayout(sliceCount: 8)
        XCTAssertEqual(layout.centerAngle(of: 0), 0, accuracy: 1e-9)
        let top = layout.labelPoint(for: 0)
        XCTAssertEqual(top.x, 0, accuracy: 1e-9)
        XCTAssertLessThan(top.y, 0, "y points down, so slice 0 must sit above the centre")
    }

    func testSlicesAdvanceClockwise() {
        let layout = RadialLayout(sliceCount: 4)
        let right = layout.labelPoint(for: 1)
        XCTAssertGreaterThan(right.x, 0)
        XCTAssertEqual(right.y, 0, accuracy: 1e-6)
        let bottom = layout.labelPoint(for: 2)
        XCTAssertGreaterThan(bottom.y, 0)
    }

    func testHitTestCentreIsClose() {
        let layout = RadialLayout(sliceCount: 6)
        XCTAssertEqual(layout.hitTest(.zero), .close)
        XCTAssertEqual(layout.hitTest(CGPoint(x: 10, y: -10)), .close)
    }

    func testHitTestOutsideRingIsNone() {
        let layout = RadialLayout(sliceCount: 6, outerRadius: 200)
        XCTAssertEqual(layout.hitTest(CGPoint(x: 0, y: -260)), .none)
        XCTAssertEqual(layout.hitTest(CGPoint(x: 1000, y: 1000)), .none)
    }

    func testHitTestMapsRingPointsToSlices() {
        let layout = RadialLayout(sliceCount: 4, centerRadius: 50, outerRadius: 200)
        XCTAssertEqual(layout.hitTest(CGPoint(x: 0, y: -150)), .slice(0))
        XCTAssertEqual(layout.hitTest(CGPoint(x: 150, y: 0)), .slice(1))
        XCTAssertEqual(layout.hitTest(CGPoint(x: 0, y: 150)), .slice(2))
        XCTAssertEqual(layout.hitTest(CGPoint(x: -150, y: 0)), .slice(3))
    }

    func testHubGapIsNotDead() {
        // Between the close button and the ring we still know which slice the pointer is in,
        // so hover and click behave predictably instead of flickering.
        let layout = RadialLayout(sliceCount: 8, centerRadius: 50, outerRadius: 200)
        let point = CGPoint(x: 0, y: -58)
        XCTAssertEqual(layout.hitTest(point), .slice(0))
    }

    func testNineSlicesBoundarySitsBetweenWedges() {
        let layout = RadialLayout(sliceCount: 9)
        let boundary = layout.angleRange(of: 1).start
        XCTAssertEqual(boundary, layout.step / 2, accuracy: 1e-9)
        let justBefore = layout.point(radius: 150, angle: boundary - 0.01)
        let justAfter = layout.point(radius: 150, angle: boundary + 0.01)
        XCTAssertEqual(layout.sliceIndex(for: justBefore), 0)
        XCTAssertEqual(layout.sliceIndex(for: justAfter), 1)
    }

    func testSliceIndexWrapsAtNegativeAngles() {
        // Up-left is 315°: it must resolve to the last slice, not a negative index.
        let layout = RadialLayout(sliceCount: 8)
        XCTAssertEqual(layout.sliceIndex(for: CGPoint(x: -100, y: -100)), 7)
        XCTAssertEqual(layout.hitTest(CGPoint(x: -100, y: -100)), .slice(7))
    }

    func testEmptyLayoutIsSafe() {
        let layout = RadialLayout(sliceCount: 0)
        XCTAssertEqual(layout.hitTest(CGPoint(x: 0, y: -100)), .none)
        XCTAssertEqual(layout.sliceIndex(for: CGPoint(x: 0, y: -100)), 0)
    }

    func testPathAlternatesOuterAndInnerArcs() {
        let layout = RadialLayout(sliceCount: 8, centerRadius: 50, outerRadius: 200)
        let path = layout.path(from: 0, to: layout.step)
        XCTAssertGreaterThan(path.count, 4)
        XCTAssertEqual(hypot(path.first!.x, path.first!.y), 200, accuracy: 0.5)
        XCTAssertEqual(hypot(path.last!.x, path.last!.y), layout.innerRadius, accuracy: 0.5)
    }

    func testKeyLabelsAreOneBased() {
        XCTAssertEqual(RadialLayout.keyLabel(forSlice: 0), "1")
        XCTAssertEqual(RadialLayout.keyLabel(forSlice: 8), "9")
        XCTAssertEqual(RadialLayout.sliceIndex(forKey: "1"), 0)
        XCTAssertEqual(RadialLayout.sliceIndex(forKey: "9"), 8)
        XCTAssertNil(RadialLayout.sliceIndex(forKey: "0"))
        XCTAssertNil(RadialLayout.sliceIndex(forKey: "a"))
    }
}

final class RadialPagingTests: XCTestCase {

    func testEmptyPagingStillShowsOnePage() {
        let paging = RadialPaging(total: 0)
        XCTAssertEqual(paging.pageCount, 1)
        XCTAssertEqual(paging.sliceCount(onPage: 0), 0)
        XCTAssertTrue(paging.items(onPage: 0).isEmpty)
    }

    func testPagesSplitByNine() {
        let paging = RadialPaging(total: 20)
        XCTAssertEqual(paging.pageCount, 3)
        XCTAssertEqual(paging.items(onPage: 0), Array(0..<9))
        XCTAssertEqual(paging.items(onPage: 1), Array(9..<18))
        XCTAssertEqual(paging.items(onPage: 2), [18, 19])
    }

    func testExactMultipleDoesNotCreateEmptyPage() {
        let paging = RadialPaging(total: 18)
        XCTAssertEqual(paging.pageCount, 2)
        XCTAssertEqual(paging.sliceCount(onPage: 1), 9)
    }

    func testPageWrapping() {
        let paging = RadialPaging(total: 20)
        XCTAssertEqual(paging.nextPage(from: 2), 0)
        XCTAssertEqual(paging.previousPage(from: 0), 2)
    }

    func testClampingPage() {
        let paging = RadialPaging(total: 20)
        XCTAssertEqual(paging.clampedPage(-5), 0)
        XCTAssertEqual(paging.clampedPage(99), 2)
    }
}

final class BookmarkTests: XCTestCase {

    func testNormalizesBareHost() {
        XCTAssertEqual(Bookmark.normalizedURL("apple.com")?.absoluteString, "https://apple.com")
        XCTAssertEqual(Bookmark.normalizedURL("  example.com/path  ")?.absoluteString, "https://example.com/path")
    }

    func testKeepsExistingScheme() {
        XCTAssertEqual(Bookmark.normalizedURL("http://example.com")?.absoluteString, "http://example.com")
    }

    func testRejectsUnopenableSchemes() {
        XCTAssertNil(Bookmark.normalizedURL("javascript:alert(1)"))
        XCTAssertNil(Bookmark.normalizedURL("file:///etc/passwd"))
        XCTAssertNil(Bookmark.normalizedURL("mailto:a@b.com"))
        XCTAssertNil(Bookmark.normalizedURL(""))
        XCTAssertNil(Bookmark.normalizedURL("   "))
        XCTAssertNil(Bookmark.normalizedURL("https://"))
    }

    func testComparisonKeyIgnoresCaseAndTrailingSlash() {
        let a = Bookmark(title: "A", url: "https://Example.com/")
        let b = Bookmark(title: "B", url: "https://example.com")
        XCTAssertEqual(a.comparisonKey, b.comparisonKey)
    }

    func testDisplayTitleFallsBackToHost() {
        let bookmark = Bookmark(title: "   ", url: "https://www.github.com/openai")
        XCTAssertEqual(bookmark.displayTitle, "github.com")
        XCTAssertEqual(bookmark.host, "github.com")
    }

    func testSubtitlePrefersFolderThenHidesDuplicateHost() {
        XCTAssertEqual(Bookmark(title: "GitHub", url: "https://github.com", folder: "Dev").subtitle, "Dev")
        XCTAssertEqual(Bookmark(title: "GitHub", url: "https://github.com").subtitle, "")
        XCTAssertEqual(Bookmark(title: "OpenAI", url: "https://openai.com").subtitle, "")
        XCTAssertEqual(Bookmark(title: "Docs", url: "https://openai.com/docs").subtitle, "openai.com")
    }
}

final class BookmarkStoreTests: XCTestCase {

    func testAddRejectsInvalidAndDuplicate() {
        let store = BookmarkStore()
        XCTAssertTrue(store.add(Bookmark(title: "A", url: "example.com"), save: false))
        XCTAssertFalse(store.add(Bookmark(title: "A again", url: "https://example.com"), save: false))
        XCTAssertFalse(store.add(Bookmark(title: "Bad", url: "javascript:void(0)"), save: false))
        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store.bookmarks[0].url, "https://example.com")
    }

    func testMergeAppendsNewAndKeepsOrder() {
        let store = BookmarkStore(bookmarks: [
            Bookmark(title: "One", url: "https://one.com"),
            Bookmark(title: "Two", url: "https://two.com"),
        ])
        let result = store.merge([
            Bookmark(title: "Two Renamed", url: "https://two.com"),
            Bookmark(title: "Three", url: "https://three.com"),
        ], save: false)
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.updated, 1)
        XCTAssertEqual(store.bookmarks.map(\.title), ["One", "Two Renamed", "Three"])
    }

    func testMergeIsIdempotent() {
        let incoming = (0..<12).map { Bookmark(title: "Site \($0)", url: "https://site\($0).com") }
        let store = BookmarkStore()
        XCTAssertEqual(store.merge(incoming, save: false).added, 12)
        let second = store.merge(incoming, save: false)
        XCTAssertEqual(second.added, 0)
        XCTAssertEqual(second.unchanged, 12)
        XCTAssertEqual(store.count, 12)
    }

    func testMergeBackfillsFolder() {
        let store = BookmarkStore(bookmarks: [Bookmark(title: "A", url: "https://a.com")])
        store.merge([Bookmark(title: "A", url: "https://a.com", folder: "Dev")], save: false)
        XCTAssertEqual(store.bookmarks[0].folder, "Dev")
    }

    func testPreviewReportsExactlyWhatTheMergeThenDoes() {
        let existing = [
            Bookmark(title: "One", url: "https://one.com"),
            Bookmark(title: "Two", url: "https://two.com"),
        ]
        let incoming = [
            Bookmark(title: "Two Renamed", url: "https://two.com"),
            Bookmark(title: "Three", url: "https://three.com"),
            Bookmark(title: "Four", url: "https://four.com"),
            Bookmark(title: "One", url: "https://one.com"),
        ]
        let store = BookmarkStore(bookmarks: existing)
        let preview = store.previewMerge(incoming)

        XCTAssertEqual(preview.result.added, 2)
        XCTAssertEqual(preview.result.updated, 1)
        XCTAssertEqual(preview.result.unchanged, 1)
        XCTAssertEqual(preview.added.map(\.title), ["Three", "Four"])

        let real = store.merge(incoming, save: false)
        XCTAssertEqual(real, preview.result)
        XCTAssertEqual(store.bookmarks.suffix(2).map(\.title), preview.added.map(\.title))
    }

    func testPreviewLeavesTheStoreAlone() {
        let store = BookmarkStore(bookmarks: [Bookmark(title: "One", url: "https://one.com")])
        _ = store.previewMerge([
            Bookmark(title: "One Renamed", url: "https://one.com"),
            Bookmark(title: "New", url: "https://new.com"),
        ])
        XCTAssertEqual(store.bookmarks.map(\.title), ["One"])
    }

    func testPreviewCountsADuplicateInsideTheImportOnce() {
        let store = BookmarkStore()
        let preview = store.previewMerge([
            Bookmark(title: "A", url: "https://a.com"),
            Bookmark(title: "A again", url: "https://a.com"),
            Bookmark(title: "Not a web link", url: "ftp://files.example.com"),
        ])
        XCTAssertEqual(preview.added.count, 1)
        XCTAssertEqual(preview.result.added, 1)
    }

    func testMoveReorders() {
        let store = BookmarkStore(bookmarks: (0..<3).map {
            Bookmark(title: "\($0)", url: "https://s\($0).com")
        })
        store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(store.bookmarks.map(\.title), ["2", "0", "1"])
    }

    func testDroppingOntoASlotLandsInThatSlot() {
        let items = (0..<5).map { Bookmark(title: "\($0)", url: "https://s\($0).com") }

        // Dragging down: lands on the target's slot, the ones between shift up.
        let down = BookmarkStore(bookmarks: items)
        XCTAssertTrue(down.move(id: items[0].id, ontoSlotOf: items[3].id))
        XCTAssertEqual(down.bookmarks.map(\.title), ["1", "2", "3", "0", "4"])

        // Dragging up: lands on the target's slot, the ones between shift down.
        let up = BookmarkStore(bookmarks: items)
        XCTAssertTrue(up.move(id: items[4].id, ontoSlotOf: items[1].id))
        XCTAssertEqual(up.bookmarks.map(\.title), ["0", "4", "1", "2", "3"])

        // Neighbours.
        let next = BookmarkStore(bookmarks: items)
        XCTAssertTrue(next.move(id: items[1].id, ontoSlotOf: items[2].id))
        XCTAssertEqual(next.bookmarks.map(\.title), ["0", "2", "1", "3", "4"])
    }

    func testDroppingOntoYourselfOrAStrangerChangesNothing() {
        let items = (0..<3).map { Bookmark(title: "\($0)", url: "https://s\($0).com") }
        let store = BookmarkStore(bookmarks: items)
        XCTAssertFalse(store.move(id: items[1].id, ontoSlotOf: items[1].id))
        XCTAssertFalse(store.move(id: UUID(), ontoSlotOf: items[1].id))
        XCTAssertFalse(store.move(id: items[1].id, ontoSlotOf: UUID()))
        XCTAssertEqual(store.bookmarks.map(\.title), ["0", "1", "2"])
    }

    func testUpdateRejectsCollision() {
        let second = Bookmark(title: "B", url: "https://b.com")
        let store = BookmarkStore(bookmarks: [Bookmark(title: "A", url: "https://a.com"), second])
        XCTAssertFalse(store.update(id: second.id, title: "B", url: "https://a.com"))
        XCTAssertTrue(store.update(id: second.id, title: "B", url: "b.org"))
        XCTAssertEqual(store.bookmark(at: 1)?.url, "https://b.org")
    }

    func testRemove() {
        let first = Bookmark(title: "A", url: "https://a.com")
        let store = BookmarkStore(bookmarks: [first, Bookmark(title: "B", url: "https://b.com")])
        XCTAssertTrue(store.remove(id: first.id))
        XCTAssertEqual(store.bookmarks.map(\.title), ["B"])
    }

    func testSaveAndLoadRoundTrip() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let file = dir.appendingPathComponent("bookmarks.json")
        let store = BookmarkStore(fileURL: file)
        store.add(Bookmark(title: "Round", url: "https://round.com", folder: "Dev"))

        let loaded = BookmarkStore.load(from: file)
        XCTAssertEqual(loaded.bookmarks.count, 1)
        XCTAssertEqual(loaded.bookmarks[0].title, "Round")
        XCTAssertEqual(loaded.bookmarks[0].folder, "Dev")
        try? FileManager.default.removeItem(at: dir)
    }

    func testCorruptStoreIsBackedUpNotFatal() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("bookmarks.json")
        try Data("not json".utf8).write(to: file)

        let loaded = BookmarkStore.load(from: file)
        XCTAssertTrue(loaded.bookmarks.isEmpty)
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("bookmarks-corrupt") }
        XCTAssertEqual(backups.count, 1)
        try? FileManager.default.removeItem(at: dir)
    }

    func testPagingReflectsStoreOrder() {
        let store = BookmarkStore(bookmarks: (0..<10).map {
            Bookmark(title: "\($0)", url: "https://s\($0).com")
        })
        XCTAssertEqual(store.bookmarks(onPage: 1).map(\.title), ["9"])
    }
}

final class HotkeySpecTests: XCTestCase {

    func testDefaultIsCommandE() {
        XCTAssertEqual(HotkeySpec.default.displayName, "⌘E")
        XCTAssertTrue(HotkeySpec.default.isValid)
    }

    func testDefaultIsNotSafariReload() {
        // ⌘R is Safari's reload, and a Carbon hot key wins over the frontmost app, so the
        // shipped default must not be ⌘R.
        XCTAssertNotEqual(HotkeySpec.default.keyCode, HotkeySpec.legacyDefault.keyCode)
        XCTAssertEqual(HotkeySpec.legacyDefault.displayName, "⌘R")
    }

    func testDefaultConflictIsMinor() {
        // ⌘E costs Safari "use selection for find", which is a nuisance, not a broken app.
        XCTAssertEqual(HotkeyConflicts.conflict(for: .default)?.severity, .minor)
    }

    func testModifierOrderInDisplayName() {
        let spec = HotkeySpec(keyCode: 49, command: true, option: true, control: true, shift: true)
        XCTAssertEqual(spec.displayName, "⌃⌥⇧⌘Space")
    }

    func testBareKeyIsInvalid() {
        XCTAssertFalse(HotkeySpec(keyCode: 15).isValid)
        XCTAssertFalse(HotkeySpec(keyCode: 15, shift: true).isValid)
        XCTAssertTrue(HotkeySpec(keyCode: 15, option: true).isValid)
    }

    func testUnknownKeyCodeStillRenders() {
        XCTAssertEqual(HotkeySpec(keyCode: 999, command: true).displayName, "⌘Key 999")
    }

    func testCodableRoundTrip() throws {
        let spec = HotkeySpec(keyCode: 49, command: true, option: true)
        let decoded = try JSONDecoder().decode(HotkeySpec.self, from: JSONEncoder().encode(spec))
        XCTAssertEqual(decoded, spec)
    }
}

final class PreferencesTests: XCTestCase {

    func testDefaults() {
        let prefs = Preferences.default
        XCTAssertEqual(prefs.hotkey, .default)
        XCTAssertTrue(prefs.showNumbers)
        XCTAssertTrue(prefs.autoSyncOnLaunch)
    }

    func testClampRadiusAndHotkey() {
        var prefs = Preferences(hotkey: HotkeySpec(keyCode: 15), menuRadius: 9000)
        prefs.clamp()
        XCTAssertEqual(prefs.menuRadius, 320)
        XCTAssertEqual(prefs.hotkey, .default)
    }

    func testMissingFieldsUseDefaults() throws {
        let data = try JSONEncoder().encode(["showNumbers": false])
        let prefs = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertFalse(prefs.showNumbers)
        XCTAssertEqual(prefs.hotkey, .default)
    }

    func testCompassIsCleanByDefaultAndWhenTheKeyIsMissing() throws {
        XCTAssertFalse(Preferences.default.compassWorn)
        // An older preferences file has no such key, so it gets the default rather than a choice
        // it never made.
        let data = try JSONEncoder().encode(["showNumbers": false])
        XCTAssertFalse(try JSONDecoder().decode(Preferences.self, from: data).compassWorn)
    }

    func testCompassWearSurvivesARoundTrip() throws {
        var prefs = Preferences()
        prefs.compassWorn = true
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(prefs))
        XCTAssertTrue(decoded.compassWorn)
    }

    func testRoundTrip() throws {
        var prefs = Preferences()
        prefs.openIn = .currentTab
        prefs.hotkey = HotkeySpec(keyCode: 49, command: true, option: true)
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(prefs))
        XCTAssertEqual(decoded, prefs)
    }
}

final class RadialSessionTests: XCTestCase {

    private func makeBookmarks(_ count: Int) -> [Bookmark] {
        (0..<count).map { Bookmark(title: "Site \($0)", url: "https://site\($0).com") }
    }

    func testToggleOpensAndCloses() {
        let session = RadialSession(paging: RadialPaging(total: 5))
        XCTAssertEqual(session.toggle(hotkeyRepeated: false), .opened(page: 0))
        XCTAssertTrue(session.isOpen)
        XCTAssertEqual(session.toggle(hotkeyRepeated: true), .closed)
        XCTAssertFalse(session.isOpen)
    }

    func testToggleWithNoBookmarksAsksForSome() {
        let session = RadialSession(paging: RadialPaging(total: 0))
        XCTAssertEqual(session.toggle(hotkeyRepeated: false), .needsMoreBookmarks)
        XCTAssertFalse(session.isOpen)
    }

    func testNumberKeyActivatesSliceOnCurrentPage() {
        let bookmarks = makeBookmarks(12)
        let session = RadialSession(paging: RadialPaging(total: 12))
        _ = session.toggle(hotkeyRepeated: false)
        _ = session.nextPage()
        XCTAssertEqual(session.activate(key: "1", bookmarks: bookmarks),
                       .activated(bookmark: bookmarks[9], index: 9))
        XCTAssertFalse(session.isOpen, "firing a slice closes the menu")
    }

    func testNumberBeyondPageIsIgnored() {
        let bookmarks = makeBookmarks(10)
        let session = RadialSession(paging: RadialPaging(total: 10))
        _ = session.toggle(hotkeyRepeated: false)
        _ = session.nextPage() // holds a single slice
        XCTAssertEqual(session.activate(key: "5", bookmarks: bookmarks), .none)
        XCTAssertTrue(session.isOpen)
    }

    func testNumberKeyWhenClosedDoesNothing() {
        let bookmarks = makeBookmarks(3)
        let session = RadialSession(paging: RadialPaging(total: 3))
        XCTAssertEqual(session.activate(key: "1", bookmarks: bookmarks), .none)
    }

    func testSliceClickActivates() {
        let bookmarks = makeBookmarks(4)
        let session = RadialSession(paging: RadialPaging(total: 4))
        _ = session.toggle(hotkeyRepeated: false)
        XCTAssertEqual(session.activate(slice: 2, bookmarks: bookmarks),
                       .activated(bookmark: bookmarks[2], index: 2))
    }

    func testCancelClosesWithoutActivating() {
        let session = RadialSession(paging: RadialPaging(total: 4))
        _ = session.toggle(hotkeyRepeated: false)
        XCTAssertEqual(session.cancel(), .closed)
        XCTAssertFalse(session.isOpen)
    }

    func testPagingWrapsAndIsIgnoredForSinglePage() {
        let single = RadialSession(paging: RadialPaging(total: 3))
        _ = single.toggle(hotkeyRepeated: false)
        XCTAssertEqual(single.nextPage(), .none)

        let multi = RadialSession(paging: RadialPaging(total: 25))
        _ = multi.toggle(hotkeyRepeated: false)
        XCTAssertEqual(multi.nextPage(), .pageChanged(page: 1))
        XCTAssertEqual(multi.nextPage(), .pageChanged(page: 2))
        XCTAssertEqual(multi.nextPage(), .pageChanged(page: 0))
        XCTAssertEqual(multi.previousPage(), .pageChanged(page: 2))
    }

    func testShrinkingStoreClampsPage() {
        let session = RadialSession(paging: RadialPaging(total: 25))
        _ = session.toggle(hotkeyRepeated: false)
        _ = session.nextPage()
        _ = session.nextPage()
        XCTAssertEqual(session.page, 2)
        session.update(paging: RadialPaging(total: 3))
        XCTAssertEqual(session.page, 0)
    }
}

final class HotkeyConflictTests: XCTestCase {

    func testCommandRIsFlaggedAsSafariReload() {
        let conflict = HotkeyConflicts.conflict(for: .legacyDefault)
        XCTAssertEqual(conflict?.owner, "Safari")
        XCTAssertEqual(conflict?.description, "reloads the page")
        XCTAssertEqual(conflict?.severity, .major)
    }

    func testControlOptionRIsFree() {
        XCTAssertNil(HotkeyConflicts.conflict(for: HotkeySpec(keyCode: 15, option: true, control: true)))
    }

    func testControlCommandRIsFree() {
        XCTAssertNil(HotkeyConflicts.conflict(for: HotkeySpec(keyCode: 15, command: true, control: true)))
    }

    func testShiftingACommandShortcutAvoidsTheConflict() {
        XCTAssertNil(HotkeyConflicts.conflict(for: HotkeySpec(keyCode: 17, command: true, shift: true)))
    }

    func testSaferAlternativeAddsControl() {
        let safer = HotkeyConflicts.saferAlternative(to: .legacyDefault)
        XCTAssertEqual(safer, HotkeySpec(keyCode: 15, command: true, control: true))
        XCTAssertNil(HotkeyConflicts.conflict(for: safer))
    }

    func testSaferAlternativeKeepsTheKeyThatWasChosen() {
        let safer = HotkeyConflicts.saferAlternative(to: .default)
        XCTAssertEqual(safer.keyCode, HotkeySpec.default.keyCode)
        XCTAssertNil(HotkeyConflicts.conflict(for: safer))
    }

    func testSaferAlternativeNeverProducesInvalidHotkey() {
        let optionOnly = HotkeySpec(keyCode: 15, option: true)
        XCTAssertTrue(HotkeyConflicts.saferAlternative(to: optionOnly).isValid)
    }
}

final class LabelFitTests: XCTestCase {

    /// The bug this locks down: a label drawn as a horizontal box at 3 o'clock used to punch
    /// through the slice walls. Every box the layout permits must sit inside its own wedge.
    func testLabelsNeverOverflowTheirSlice() {
        for count in 2...RadialLayout.maxSlicesPerPage {
            for radius in [140.0, 200.0, 320.0] as [CGFloat] {
                let layout = RadialLayout(sliceCount: count, centerRadius: radius * 0.26, outerRadius: radius)
                for index in 0..<count {
                    for height in [20.0, 34.0] as [CGFloat] {
                        let width = layout.labelWidthLimit(for: index, height: height, pad: 4)
                        XCTAssertGreaterThan(width, 0, "n=\(count) r=\(radius) i=\(index)")
                        let anchor = layout.labelPoint(for: index)
                        for dx in [-width / 2, width / 2] {
                            for dy in [-height / 2, height / 2] {
                                let corner = CGPoint(x: anchor.x + dx, y: anchor.y + dy)
                                XCTAssertTrue(
                                    layout.sliceContains(corner, index: index, inset: 0),
                                    "n=\(count) r=\(radius) i=\(index) h=\(height) corner \(corner) escaped"
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    func testTallerBoxesGetLessRoom() {
        let layout = RadialLayout(sliceCount: 9, centerRadius: 52, outerRadius: 200)
        let short = layout.labelWidthLimit(for: 2, height: 20, pad: 6)
        let tall = layout.labelWidthLimit(for: 2, height: 40, pad: 6)
        XCTAssertLessThanOrEqual(tall, short)
    }

    func testLimitsArePositiveAtEverySliceCount() {
        // A zero limit would mean labels are invisible, which reads as a rendering bug.
        for count in 1...RadialLayout.maxSlicesPerPage {
            let layout = RadialLayout(sliceCount: count, centerRadius: 52, outerRadius: 200)
            for index in 0..<count {
                XCTAssertGreaterThan(layout.labelWidthLimit(for: index, height: 34, pad: 6), 40)
            }
        }
    }
}

final class PreferencesMigrationTests: XCTestCase {

    func testMigratesTheOldCommandRDefault() {
        var prefs = Preferences(hotkey: HotkeySpec.legacyDefault)
        prefs.migrateLegacyHotkey()
        XCTAssertEqual(prefs.hotkey, .default)
        XCTAssertTrue(prefs.hotkeyMigrated)
    }

    func testMigrationIsOneShot() {
        var prefs = Preferences(hotkey: HotkeySpec.legacyDefault)
        prefs.migrateLegacyHotkey()
        // Someone who deliberately goes back to ⌘R afterwards keeps it.
        prefs.hotkey = HotkeySpec.legacyDefault
        prefs.migrateLegacyHotkey()
        XCTAssertEqual(prefs.hotkey, HotkeySpec.legacyDefault)
    }

    func testMigrationLeavesACustomShortcutAlone() {
        let custom = HotkeySpec(keyCode: 49, command: true, control: true)
        var prefs = Preferences(hotkey: custom)
        prefs.migrateLegacyHotkey()
        XCTAssertEqual(prefs.hotkey, custom)
    }

    func testOlderPreferencesFileDefaultsOnboardingToDone() throws {
        // A file written before onboarding existed means the user is not new.
        let json = #"{"hotkey":{"keyCode":15,"command":true,"option":false,"control":false,"shift":false},"menuRadius":200}"#
        let prefs = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        XCTAssertTrue(prefs.hasCompletedOnboarding)
        XCTAssertFalse(prefs.hotkeyMigrated)
    }

    func testFreshPreferencesAskForOnboarding() {
        XCTAssertFalse(Preferences.default.hasCompletedOnboarding)
    }
}

final class RadialSessionPagingTests: XCTestCase {

    func testSetPageJumpsDirectly() {
        let session = RadialSession(paging: RadialPaging(total: 30))
        _ = session.toggle(hotkeyRepeated: false)
        XCTAssertEqual(session.setPage(2), .pageChanged(page: 2))
        XCTAssertEqual(session.page, 2)
    }

    func testSetPageIgnoresSamePageAndOutOfRange() {
        let session = RadialSession(paging: RadialPaging(total: 30))
        _ = session.toggle(hotkeyRepeated: false)
        XCTAssertEqual(session.setPage(0), .none)
        XCTAssertEqual(session.setPage(99), .pageChanged(page: 3))
        XCTAssertEqual(session.setPage(99), .none)
    }

    func testSetPageWhenClosedDoesNothing() {
        let session = RadialSession(paging: RadialPaging(total: 30))
        XCTAssertEqual(session.setPage(1), .none)
        XCTAssertEqual(session.page, 0)
    }
}

final class DrawableRangeTests: XCTestCase {

    /// Regression: slice 0 wraps at 12 o'clock, so `end < start`. Comparing them made the
    /// top slice vanish from the rendered menu.
    func testTopSliceIsDrawable() {
        let layout = RadialLayout(sliceCount: 9)
        let drawn = layout.drawableRange(of: 0, inset: 0.018)
        XCTAssertGreaterThan(drawn.sweep, 0)
        XCTAssertEqual(Double(drawn.sweep), Double(layout.step - 0.036), accuracy: 1e-9)
    }

    func testEverySliceHasAPositiveSweep() {
        for count in 2...9 {
            let layout = RadialLayout(sliceCount: count)
            for index in 0..<count {
                let drawn = layout.drawableRange(of: index, inset: 0.005)
                XCTAssertGreaterThan(drawn.sweep, 0, "slice \(index) of \(count)")
                XCTAssertEqual(Double(drawn.sweep), Double(layout.step - 0.01), accuracy: 1e-9)
            }
        }
    }

    /// Regression: one bookmark must fill the circle. `normalize(2π)` is 0, so a naive
    /// sweep calculation drew nothing at all.
    func testSingleSliceFillsTheCircleWithoutASeam() {
        let layout = RadialLayout(sliceCount: 1)
        for inset in [0, 0.018, 0.5] as [CGFloat] {
            let drawn = layout.drawableRange(of: 0, inset: inset)
            XCTAssertEqual(Double(drawn.start), 0, accuracy: 1e-9)
            XCTAssertEqual(Double(drawn.sweep), 2 * Double.pi, accuracy: 1e-9)
        }
    }

    func testNoSlicesDrawsNothing() {
        let layout = RadialLayout(sliceCount: 0)
        XCTAssertEqual(layout.drawableRange(of: 0, inset: 0).sweep, 0)
    }

    func testTopSliceStartsJustBeforeTwelveOClock() {
        let layout = RadialLayout(sliceCount: 4)
        let drawn = layout.drawableRange(of: 0, inset: 0)
        // 12 o'clock is angle 0, so the slice starts a quarter turn earlier.
        XCTAssertEqual(Double(drawn.start), Double(RadialLayout.normalize(-layout.step / 2)), accuracy: 1e-9)
        let end = RadialLayout.normalize(drawn.start + drawn.sweep)
        XCTAssertEqual(Double(end), Double(RadialLayout.normalize(layout.step / 2)), accuracy: 1e-9)
    }

    func testDrawableRangeStaysInsideTheSlicesOwnArc() {
        let layout = RadialLayout(sliceCount: 7)
        for index in 0..<7 {
            let drawn = layout.drawableRange(of: index, inset: 0.01)
            let mid = RadialLayout.normalize(drawn.start + drawn.sweep / 2)
            let expected = layout.centerAngle(of: index)
            let delta = abs(Double(mid) - Double(expected))
            let wrapped = min(delta, 2 * Double.pi - delta)
            XCTAssertLessThan(wrapped, 1e-9, "slice \(index) is centred correctly")
        }
    }

    func testOversizedInsetCannotInvertTheSlice() {
        let layout = RadialLayout(sliceCount: 9)
        let drawn = layout.drawableRange(of: 0, inset: 10)
        XCTAssertGreaterThanOrEqual(drawn.sweep, 0)
    }
}

// MARK: - Miniature geometry

final class MiniatureLayoutTests: XCTestCase {

    /// The bug this locks down: `RadialLayout` used to floor the hub gap at 13pt and the ring
    /// depth at 40pt, both in absolute points. On the 26pt slot gutter in the manager that
    /// made the wedges render at ~59pt radius, so they escaped the row and drew over the
    /// bookmark names — "the little radial slices don't line up".
    func testMiniatureStaysInsideItsFrame() {
        let sizes: [CGFloat] = [26, 40, 92, 120]
        for side in sizes {
            let layout = RadialLayout(
                sliceCount: 9,
                centerRadius: side * 0.20,
                outerRadius: side * 0.47,
                hubGap: side * 0.045
            )
            XCTAssertLessThanOrEqual(
                layout.outerRadius, side / 2,
                "the ring escaped its \(side)pt frame"
            )
            XCTAssertGreaterThan(
                layout.ringDepth, 0,
                "a \(side)pt dial collapsed to a zero-width ring"
            )
            XCTAssertGreaterThan(
                layout.innerRadius, layout.centerRadius,
                "a \(side)pt dial lost its hub gap"
            )
        }
    }

    /// The gutter mark must read as a wedge ring, not a plain dot: the ring needs real
    /// depth at the size it actually renders (26pt).
    func testGutterRingHasVisibleDepth() {
        let side: CGFloat = 26
        let layout = RadialLayout(
            sliceCount: 9,
            centerRadius: side * 0.20,
            outerRadius: side * 0.47,
            hubGap: side * 0.045
        )
        XCTAssertGreaterThan(layout.ringDepth, 5, "the ring is too thin to read at 26pt")
        XCTAssertGreaterThan(layout.centerRadius, 4, "the hub vanished")
        XCTAssertLessThanOrEqual(layout.outerRadius, side / 2)
    }

    /// The gap and the depth have to scale with the dial, not be fixed constants.
    func testHubGapAndDepthScaleWithTheDial() {
        let small = RadialLayout(sliceCount: 9, centerRadius: 7.5, outerRadius: 12, hubGap: 1.3)
        let large = RadialLayout(sliceCount: 9, centerRadius: 52, outerRadius: 200)
        XCTAssertLessThan(small.ringDepth, large.ringDepth)
        XCTAssertLessThan(small.innerRadius - small.centerRadius, large.innerRadius - large.centerRadius)
    }

    /// Defaults are unchanged for the real menu, so the dial itself does not move.
    func testDefaultDialGeometryIsUnchanged() {
        let layout = RadialLayout(sliceCount: 9, centerRadius: 52, outerRadius: 200)
        XCTAssertEqual(layout.innerRadius, 52 + 200 * 0.085, accuracy: 1e-9)
        XCTAssertEqual(layout.outerRadius, 200, accuracy: 1e-9)
    }

    /// A hub gap big enough to invert the ring must not produce a negative-depth dial.
    func testAbsurdHubGapStillLeavesARing() {
        let layout = RadialLayout(sliceCount: 9, centerRadius: 10, outerRadius: 100, hubGap: 500)
        XCTAssertGreaterThan(layout.outerRadius, layout.innerRadius)
    }
}

// MARK: - Browser catalogue and open plan

final class BrowserTests: XCTestCase {

    func testCatalogueHasUniqueBundleIdentifiers() {
        let ids = Browser.catalogue.map(\.bundleID)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testUnknownOrMissingIdentifierFallsBackToSafari() {
        XCTAssertEqual(Browser.browser(forBundleID: nil), .safari)
        XCTAssertEqual(Browser.browser(forBundleID: "com.example.nope"), .safari)
        XCTAssertEqual(Browser.browser(forBundleID: "com.google.Chrome"), .chrome)
    }

    /// Preferences saved before this setting existed must keep opening in Safari.
    func testOlderPreferencesDefaultToSafari() throws {
        let data = try JSONEncoder().encode(["showNumbers": true])
        let prefs = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertEqual(prefs.browserBundleID, Browser.safari.bundleID)
        XCTAssertEqual(prefs.browser, .safari)
    }

    func testBrowserChoiceSurvivesARoundTrip() throws {
        var prefs = Preferences()
        prefs.browserBundleID = Browser.chrome.bundleID
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(prefs))
        XCTAssertEqual(decoded.browser, .chrome)
    }

    func testInstalledListKeepsTheSelectedBrowser() {
        // Nothing but Chrome installed, but the user picked Firefox: the picker must not
        // silently drop their choice.
        let available = BrowserCatalog.available(selected: .firefox) { id in
            id == Browser.chrome.bundleID
        }
        XCTAssertEqual(available.first, .firefox)
        XCTAssertTrue(available.contains(.chrome))
        XCTAssertFalse(available.contains(.safari))
    }

    /// The reported bug: "my setting says new tab, but GitHub opens the tab that already has
    /// GitHub in it". Launch Services reuses an existing tab, so a scriptable browser has to
    /// be asked for a literal new tab instead.
    func testNewTabIsScriptedRatherThanHandedToLaunchServices() {
        XCTAssertEqual(OpenPlan.resolve(target: .newTab, in: .safari), .scripted(.newTab))
        XCTAssertEqual(OpenPlan.resolve(target: .newTab, in: .chrome), .scripted(.newTab))
    }

    func testUnscriptableBrowserFallsBackToPlainOpen() {
        XCTAssertEqual(OpenPlan.resolve(target: .newTab, in: .firefox), .launchServices)
        XCTAssertEqual(OpenPlan.resolve(target: .currentTab, in: .firefox), .launchServices)
        XCTAssertEqual(OpenPlan.resolve(target: .newWindow, in: .arc), .launchServices)
    }

    func testHonestyAboutTargetsPerBrowser() {
        XCTAssertTrue(OpenPlan.honoursTarget(.currentTab, in: .safari))
        XCTAssertTrue(OpenPlan.honoursTarget(.currentTab, in: .chrome))
        // A plain open cannot promise a specific tab, but a new tab is always at least true.
        XCTAssertFalse(OpenPlan.honoursTarget(.currentTab, in: .firefox))
        XCTAssertTrue(OpenPlan.honoursTarget(.newTab, in: .firefox))
    }

    func testDescriptionsNameTheBrowserAndAdmitFallbacks() {
        XCTAssertEqual(
            OpenPlan.description(for: .newWindow, in: .chrome),
            "New window in Google Chrome"
        )
        let degraded = OpenPlan.description(for: .currentTab, in: .firefox)
        XCTAssertTrue(degraded.contains("new tab"), degraded)
        XCTAssertTrue(degraded.contains("Firefox"), degraded)
    }
}

// MARK: - 3D tilt

final class RadialTiltTests: XCTestCase {

    func testFlatTiltIsTheIdentity() {
        let tilt = RadialTilt.flat
        XCTAssertTrue(tilt.isFlat)
        let point = CGPoint(x: 120, y: -80)
        XCTAssertEqual(tilt.project(point), point)
        XCTAssertEqual(tilt.unproject(point), point)
        XCTAssertEqual(tilt.scale(at: point), 1, accuracy: 1e-12)
    }

    /// Hover and click must keep landing on the same slice after the dial leans, so the
    /// projection has to be invertible to floating-point accuracy.
    func testProjectionRoundTripsAcrossTheDial() {
        for pitch in [-0.19, -0.05, 0.0, 0.05, 0.19] as [CGFloat] {
            for roll in [-0.19, -0.05, 0.0, 0.05, 0.19] as [CGFloat] {
                let tilt = RadialTilt(pitch: pitch, roll: roll, eyeDistance: 800)
                for x in stride(from: -260.0, through: 260.0, by: 40) {
                    for y in stride(from: -260.0, through: 260.0, by: 40) {
                        let point = CGPoint(x: x, y: y)
                        let restored = tilt.unproject(tilt.project(point))
                        XCTAssertEqual(restored.x, point.x, accuracy: 1e-6)
                        XCTAssertEqual(restored.y, point.y, accuracy: 1e-6)
                    }
                }
            }
        }
    }

    /// The point the dial leans toward must come *closer* to the viewer, i.e. get bigger.
    /// A projection that shrinks that side looks like it is leaning away and reads wrong.
    func testDialLeansTowardThePointer() {
        let radius: CGFloat = 220
        for pointer in [
            CGPoint(x: 0, y: 200), CGPoint(x: 0, y: -200),
            CGPoint(x: 200, y: 0), CGPoint(x: -200, y: 0),
        ] {
            let tilt = RadialTilt(leaningToward: pointer, radius: radius)
            XCTAssertFalse(tilt.isFlat, "no tilt toward \(pointer)")
            let opposite = CGPoint(x: -pointer.x, y: -pointer.y)
            let near = tilt.scale(at: pointer)
            let far = tilt.scale(at: opposite)
            XCTAssertGreaterThan(near, far, "the dial leaned away from \(pointer)")
            XCTAssertGreaterThan(near, 1, "the near side did not grow toward \(pointer)")
            XCTAssertLessThan(far, 1, "the far side did not recede from \(pointer)")
        }
    }

    func testTiltIsEasedInFromTheCentreAndBoundedAtTheRim() {
        let radius: CGFloat = 200
        let centre = RadialTilt(leaningToward: .zero, radius: radius)
        XCTAssertTrue(centre.isFlat, "the hub should not tip the dial")

        let edge = RadialTilt(leaningToward: CGPoint(x: 200, y: 0), radius: radius)
        let angle = max(abs(edge.pitch), abs(edge.roll))
        XCTAssertLessThanOrEqual(angle, RadialTilt.maxAngle + 1e-9)

        // A pointer held past the rim must not tilt harder than the maximum.
        let beyond = RadialTilt(leaningToward: CGPoint(x: 900, y: 0), radius: radius)
        XCTAssertLessThanOrEqual(max(abs(beyond.pitch), abs(beyond.roll)), RadialTilt.maxAngle + 1e-9)

        let halfway = RadialTilt(leaningToward: CGPoint(x: 100, y: 0), radius: radius)
        XCTAssertLessThan(max(abs(halfway.pitch), abs(halfway.roll)), angle)
    }

    /// A lean big enough to see: at the rim the near/far size difference should be around a
    /// tenth, not the 4% an earlier 6° setting produced (which nobody could perceive).
    func testMaximumTiltIsActuallyPerceptible() {
        let radius: CGFloat = 200
        let tilt = RadialTilt(leaningToward: CGPoint(x: 0, y: radius), radius: radius)
        let near = tilt.scale(at: CGPoint(x: 0, y: radius))
        let far = tilt.scale(at: CGPoint(x: 0, y: -radius))
        let asymmetry = (near - far) / far
        XCTAssertGreaterThan(asymmetry, 0.07, "the lean is too subtle to see")
        XCTAssertLessThan(asymmetry, 0.25, "the lean tips past an obvious ring")
    }

    func testZeroRadiusTiltDoesNotCrash() {
        let tilt = RadialTilt(leaningToward: CGPoint(x: 10, y: 10), radius: 0)
        XCTAssertTrue(tilt.isFlat)
    }
}

/// The compass's geometry is load-bearing in a way the drawing never was: the whole menu is
/// hit tested through the same projection that draws it, so a disagreement between the two
/// fires the wrong bookmark. These pin the exactness that freedom assumes.
final class CompassCameraTests: XCTestCase {

    func testLevelCameraIsTheIdentity() {
        let camera = CompassCamera.level
        let point = CGPoint(x: 143, y: -87)
        let projected = camera.project(Point3D(x: point.x, y: point.y))
        XCTAssertEqual(projected.point.x, point.x, accuracy: 1e-9)
        XCTAssertEqual(projected.point.y, point.y, accuracy: 1e-9)
        XCTAssertEqual(projected.depthScale, 1, accuracy: 1e-9)
    }

    /// The case for building this on top of `RadialTilt` rather than beside it.
    func testOnTheCardPlaneItAgreesWithRadialTiltExactly() {
        let tilt = RadialTilt(pitch: 0.13, roll: -0.09, eyeDistance: 820)
        let camera = CompassCamera(tilt: tilt)
        for radius in stride(from: CGFloat(0), through: 220, by: 20) {
            for degrees in stride(from: 0, to: 360, by: 17) {
                let angle = CGFloat(degrees) * .pi / 180
                let point = Point3D(radius: radius, angle: angle)
                let viaTilt = tilt.project(CGPoint(x: point.x, y: point.y))
                let viaCamera = camera.project(point).point
                XCTAssertEqual(viaCamera.x, viaTilt.x, accuracy: 1e-9,
                               "x disagreed at r=\(radius) θ=\(degrees)")
                XCTAssertEqual(viaCamera.y, viaTilt.y, accuracy: 1e-9,
                               "y disagreed at r=\(radius) θ=\(degrees)")
            }
        }
    }

    /// And the inverse is the same inverse, which is what keeps clicks on the right slice.
    func testUnprojectionRecoversTheCard() {
        let camera = CompassCamera(pitch: 0.17, roll: -0.12, eyeDistance: 640)
        for radius in stride(from: CGFloat(10), through: 200, by: 19) {
            for degrees in stride(from: 0, to: 360, by: 23) {
                let angle = CGFloat(degrees) * .pi / 180
                let card = CGPoint(x: radius * sin(angle), y: -radius * cos(angle))
                let screen = camera.project(Point3D(x: card.x, y: card.y)).point
                let recovered = camera.unprojectToCard(screen)
                XCTAssertEqual(recovered.x, card.x, accuracy: 1e-6)
                XCTAssertEqual(recovered.y, card.y, accuracy: 1e-6)
            }
        }
    }

    /// Nearest-the-viewer points must come out bigger, or the "3D" is a flat squash.
    func testNearSideIsDrawnLargerThanTheFarSide() {
        let camera = CompassCamera(pitch: 0.19, roll: 0, eyeDistance: 800)
        let near = camera.project(Point3D(radius: 200, angle: .pi)).depthScale
        let far = camera.project(Point3D(radius: 200, angle: 0)).depthScale
        XCTAssertGreaterThan(near, far)
    }

    /// Height is what makes the case a box rather than a disc.
    func testDepthMovesPointsUnderTheCamera() {
        let camera = CompassCamera(pitch: 0.15, roll: 0.10, eyeDistance: 700)
        let flat = camera.project(Point3D(x: 120, y: 60, z: 0)).point
        let raised = camera.project(Point3D(x: 120, y: 60, z: -40)).point
        XCTAssertNotEqual(flat.y, raised.y, accuracy: 1e-6)
    }
}

final class CompassMetricsTests: XCTestCase {

    func testTheOpenLidIsAtLeastAsWideAsTheCaseAndScalesWithIt() {
        let small = CompassMetrics(cardRadius: 100)
        let large = CompassMetrics(cardRadius: 200)
        // A window sized to the case alone would clip the lid.
        XCTAssertGreaterThan(small.lidHalfWidth(), small.caseRadius)
        XCTAssertEqual(large.lidHalfWidth(), small.lidHalfWidth() * 2, accuracy: 1e-6)
    }

    func testEverythingScalesFromTheCardRadius() {
        let small = CompassMetrics(cardRadius: 100)
        let large = CompassMetrics(cardRadius: 200)
        XCTAssertEqual(large.caseRadius, small.caseRadius * 2, accuracy: 1e-9)
        XCTAssertEqual(large.hubRadius, small.hubRadius * 2, accuracy: 1e-9)
        XCTAssertEqual(large.labelRadius, small.labelRadius * 2, accuracy: 1e-9)
    }

    func testWedgeNamesPrintAtOneSizePerPage() {
        // The size is a function of the card and the slice count only, so no name on a page can
        // end up smaller than its neighbours.
        let metrics = CompassMetrics(cardRadius: 200)
        for count in 2...8 {
            XCTAssertEqual(metrics.labelFontSize(sliceCount: count), metrics.labelFontSize(sliceCount: 8))
        }
        XCTAssertLessThanOrEqual(metrics.labelFontSize(sliceCount: 9), metrics.labelFontSize(sliceCount: 8))
    }

    func testWedgeNamesNeverPrintBelowTheFloor() {
        for radius in [110.0, 140.0, 200.0, 320.0] as [CGFloat] {
            let metrics = CompassMetrics(cardRadius: radius)
            for count in 1...RadialLayout.maxSlicesPerPage {
                XCTAssertGreaterThanOrEqual(
                    metrics.labelFontSize(sliceCount: count), CompassMetrics.minimumLabelSize
                )
            }
        }
        // At the default size names are comfortably larger than the ~8pt the shrink-to-fit
        // loop used to leave the longest ones at.
        XCTAssertGreaterThanOrEqual(CompassMetrics(cardRadius: 200).labelFontSize(sliceCount: 8), 14)
    }

    func testLabelsKeepRoomForTwoLinesInsideTheirWedge() {
        // Two lines of the label size must fit a wedge at every count, or wrapping would just
        // move the overflow from width to height.
        let metrics = CompassMetrics(cardRadius: 200)
        for count in 2...RadialLayout.maxSlicesPerPage {
            let layout = RadialLayout(
                sliceCount: count, centerRadius: metrics.hubRadius, outerRadius: metrics.sectorOutset
            )
            let height = metrics.labelFontSize(sliceCount: count) * 2.4
            for index in 0..<count {
                XCTAssertGreaterThan(
                    layout.labelWidthLimit(for: index, radius: metrics.labelRadius, height: height, pad: metrics.labelPad),
                    50,
                    "n=\(count) i=\(index)"
                )
            }
        }
    }

    func testBandsAreOrderedOutwardFromTheHub() {
        let metrics = CompassMetrics(cardRadius: 200)
        XCTAssertLessThan(metrics.hubRadius, metrics.sectorInset)
        XCTAssertLessThan(metrics.sectorInset, metrics.labelRadius)
        XCTAssertLessThan(metrics.labelRadius, metrics.sectorOutset)
        XCTAssertLessThan(metrics.sectorOutset, metrics.scaleInset)
        XCTAssertLessThan(metrics.numeralRadius, metrics.scaleOutset)
        XCTAssertLessThan(metrics.scaleOutset, metrics.caseRadius)
    }

    func testLugHangsBelowTheCase() {
        let metrics = CompassMetrics(cardRadius: 200)
        XCTAssertGreaterThan(metrics.lugReach, metrics.caseRadius)
    }

    /// An open lid stands a full diameter from its hinge, which is why an open compass is much
    /// taller than it is wide — and why the dial has to be fitted to the screen, not centred.
    func testOpenInstrumentIsMuchTallerThanItIsWide() {
        let metrics = CompassMetrics(cardRadius: 200)
        XCTAssertGreaterThan(metrics.openHeight, metrics.caseRadius * 2.5)
    }

    func testFittingShrinksRatherThanOverflowing() {
        let metrics = CompassMetrics(cardRadius: 320)
        let fitted = metrics.fitted(toHeight: 600)
        XCTAssertLessThan(fitted.cardRadius, metrics.cardRadius)
        XCTAssertLessThanOrEqual(fitted.openHeight, 600 + 1)
    }

    func testFittingLeavesAComfortableInstrumentAlone() {
        let metrics = CompassMetrics(cardRadius: 160)
        XCTAssertEqual(metrics.fitted(toHeight: 2000), metrics)
    }

    /// The floor is legibility: below it the numerals stop being readable and the keyboard
    /// mapping becomes guesswork, so it beats fitting the screen.
    func testFittingRefusesToGoIllegiblySmall() {
        let metrics = CompassMetrics(cardRadius: 320)
        XCTAssertGreaterThanOrEqual(metrics.fitted(toHeight: 200).cardRadius, 110)
    }
}

final class CompassLidTests: XCTestCase {

    private let metrics = CompassMetrics(cardRadius: 200)

    func testShutLidLeavesPointsWhereTheyWere() {
        let lid = CompassLid(metrics: metrics, openness: 0)
        let point = Point3D(x: 60, y: -180)
        let swung = lid.swing(point)
        XCTAssertEqual(swung.x, point.x, accuracy: 1e-9)
        XCTAssertEqual(swung.y, point.y, accuracy: 1e-9)
        XCTAssertEqual(swung.z, point.z, accuracy: 1e-9)
    }

    /// The bug the design harness found: a lid smaller than the case detaches as it opens.
    /// With the hinge on the disc's own rim, the hinge line is a fixed point at every angle.
    func testHingeLineNeverMoves() {
        for steps in 0...20 {
            let lid = CompassLid(metrics: metrics, openness: CGFloat(steps) / 20)
            for x in stride(from: CGFloat(-200), through: 200, by: 50) {
                let onHinge = Point3D(x: x, y: lid.hingeY, z: lid.hingeZ)
                let swung = lid.swing(onHinge)
                XCTAssertEqual(swung.x, onHinge.x, accuracy: 1e-9)
                XCTAssertEqual(swung.y, onHinge.y, accuracy: 1e-9)
                XCTAssertEqual(swung.z, onHinge.z, accuracy: 1e-9)
            }
        }
    }

    /// The lid closes *down over* the case, so its far edge is the bottom of the disc: a full
    /// diameter from the hinge, not zero. Opening swings that edge up past the hinge and out
    /// toward the viewer.
    func testOpeningLiftsTheFarEdgeUpAndTowardTheViewer() {
        let shut = CompassLid(metrics: metrics, openness: 0)
        let open = CompassLid(metrics: metrics, openness: 1)
        let farEdge = Point3D(x: 0, y: shut.hingeY + 2 * metrics.lidRadius)
        XCTAssertGreaterThan(shut.swing(farEdge).y, 0, "shut, the lid's far edge sits over the case")
        XCTAssertLessThan(open.swing(farEdge).y, shut.hingeY,
                          "open, it must have risen clear above the hinge")
        XCTAssertGreaterThan(open.swing(farEdge).z, shut.swing(farEdge).z,
                             "and swung out toward the viewer")
    }

    /// A shut lid has to actually shut: it must cover the card it closes over.
    ///
    /// This is the constraint that decides `lidRadius`, and it is the one that is easy to get
    /// wrong by eye. Making the lid smaller makes the *open* instrument less top-heavy, which
    /// is tempting, but `cardRadius / caseRadius` sets a hard floor: below it the lid no longer
    /// reaches across the dial and the "closed" compass has paper showing past its own lid.
    func testTheShutLidCoversTheCard() {
        let lid = CompassLid(metrics: metrics, openness: 0)
        // The lid is centred on `x = 0` and hinged on its own top rim, so `farEdge` simplifies to
        // exactly `lidRadius`. That one number therefore settles both axes: it must clear the
        // card's radius in `x`, and the same inequality puts the far edge past `+cardRadius` in
        // `y`. Asserting anything against `-lid.hingeY` here would compare the radius to itself.
        let farEdge = lid.hingeY + 2 * metrics.lidRadius
        XCTAssertEqual(farEdge, metrics.lidRadius, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(farEdge, metrics.cardRadius,
                                    "a smaller lid leaves a crescent of card uncovered when shut")
    }

    /// The hinge sits exactly on the lid's own rim, and that rim is inside the case's radius
    /// but outside the card's.
    ///
    /// Pivot-on-the-rim is what stops the lid floating free as it swings: every point on the
    /// hinge line is a fixed point of the rotation. The two radius inequalities are what make a
    /// pocket compass work — the lid closes inside the case's raised lip, and it is still wide
    /// enough to cover the card.
    func testHingeSitsOnTheLidRimBetweenCardAndCase() {
        let lid = CompassLid(metrics: metrics, openness: 0)
        XCTAssertEqual(lid.hingeY, -metrics.lidRadius, accuracy: 1e-9)
        XCTAssertEqual(lid.radius, metrics.lidRadius, accuracy: 1e-9)
        XCTAssertLessThan(metrics.lidRadius, metrics.caseRadius,
                          "the lid closes inside the case's lip")
        XCTAssertGreaterThan(metrics.lidRadius, metrics.cardRadius,
                             "and it is wider than the card it covers")
    }

    /// The lid has to lean well past vertical. At 90° it is exactly edge-on to the camera and
    /// projects to a flat sliver, which reads as a plate seen edge-on rather than an open lid.
    ///
    /// The bound is 110°, not 120°: the value is tuned by eye at 120° and an assertion that sits
    /// exactly on the chosen number turns any downward nudge into a failure for reasons that
    /// have nothing to do with the property being tested. What matters is that the lid is
    /// clearly past vertical, and the height/width check below pins that directly.
    func testTheOpenLidShowsItsFaceRatherThanItsEdge() {
        XCTAssertGreaterThan(CompassMetrics.lidOpenAngle, .pi / 2 + .pi / 9)
        let open = CompassLid(metrics: metrics, openness: 1)
        let camera = CompassCamera(tilt: RadialTilt(pitch: 0, roll: 0,
                                                   eyeDistance: metrics.cardRadius * 8))
        let near = camera.project(open.swing(Point3D(x: 0, y: metrics.lidRadius * 0.9, z: 0))).point
        let far = camera.project(open.swing(Point3D(x: 0, y: -metrics.lidRadius * 0.9, z: 0))).point
        let side = camera.project(open.swing(Point3D(x: metrics.lidRadius * 0.9, y: 0, z: 0))).point
        let height = abs(near.y - far.y)
        let width = abs(side.x) * 2
        XCTAssertGreaterThan(height / width, 0.45,
                             "the lid's face must project at least this tall relative to its width")
    }

    /// Straight up is the moment the lid stands perpendicular to the card — the pose that
    /// makes its inside face most legible.
    func testAtRightAnglesTheLidStandsSquareToTheCard() {
        let quarter = CompassLid(
            metrics: metrics,
            openness: (.pi / 2) / CompassMetrics.lidOpenAngle
        )
        let farEdge = Point3D(x: 0, y: quarter.hingeY + 2 * metrics.lidRadius, z: quarter.hingeZ)
        let swung = quarter.swing(farEdge)
        XCTAssertEqual(swung.y, quarter.hingeY, accuracy: 0.5)
        XCTAssertEqual(swung.z - quarter.hingeZ, 2 * metrics.lidRadius, accuracy: 0.5)
    }

    /// The lid must not lag the case, whether it is opening or closing.
    ///
    /// This is the shape of the "⌘E appears, pauses, then flips the lid" complaint. Geometry alone
    /// cannot catch it: both poses are valid, it is the *timing* that reads as a stutter. The lid
    /// is a `LidHinge` now, flicked on the first frame, so it never waits for the box; what has to
    /// be pinned is that it also does not run on long after the box has landed, and that the card
    /// is reachable by the time the box is mostly up. Closing runs the other way round: the lid
    /// has to be shut before the box is gone, or the case vanishes with the lid still in the air.
    func testLidDoesNotFallBehindTheCaseItSitsIn() {
        /// Time for a spring to cross `threshold`, stepped at the same rate as the hinge below.
        func timeTo(_ threshold: Double, from start: Double = 0, target: Double = 1,
                    stiffness: Double, damping: Double, kick: Double = 0) -> Double {
            var value = start, speed = kick, time = 0.0
            let dt = 1.0 / 120
            let rising = target > start
            while time < 2 {
                speed += (stiffness * (target - value) - damping * speed) * dt
                value += speed * dt
                time += dt
                let reached = rising ? value >= threshold : value <= threshold
                if reached { return time }
            }
            return time
        }
        let frame = 1.0 / 120

        // Opening: the box and the hinge are stepped together, so both readings are taken at the
        // same instant.
        var box = (value: 0.0, speed: 6.0)
        var hinge = LidHinge()
        hinge.release()
        var time = 0.0
        var cleared: (time: Double, box: Double)?
        var landed: Double?
        while time < 2, cleared == nil || landed == nil {
            box.speed += (300 * (1 - box.value) - 30 * box.speed) * frame
            box.value += box.speed * frame
            hinge.step(frame)
            time += frame
            if cleared == nil, CompassLid(metrics: metrics, openness: CGFloat(hinge.openness)).revealsCard {
                cleared = (time, box.value)
            }
            if landed == nil, hinge.impact > 0 { landed = time }
        }
        guard let reached = cleared, let landing = landed else {
            XCTFail("the lid never cleared the card or never landed")
            return
        }
        // The card opens at ~135ms, with the box well up, so a click cannot land on a slice the user
        // has not seen come up. Not so early that it is a flick, not so late that the box has long
        // since stopped.
        XCTAssertGreaterThanOrEqual(reached.time, 0.08, "the lid should not clear the card in a flick")
        XCTAssertLessThanOrEqual(reached.time, 0.20, "the lid should clear the card by about 150ms")
        XCTAssertGreaterThanOrEqual(reached.box, 0.5, "the box should be at least half risen when the card opens")
        // The lid lands on its stop as the case settles: the stop is felt as a tap on the box, so it
        // has to arrive while the box is still finishing, not a beat after it.
        let boxSettled = timeTo(0.98, stiffness: 300, damping: 30, kick: 6)
        XCTAssertEqual(landing, boxSettled, accuracy: 0.10,
                       "the lid should land as the box settles, as one gesture")
        XCTAssertLessThan(landing, 0.40, "and the whole opening should still be one beat")

        // Closing has no kick: the lid must be shut before the box is gone (zero).
        var closing = LidHinge()
        closing.release()
        while !(closing.angle == closing.stop) && time < 4 {
            closing.step(frame)
            time += frame
        }
        closing.shut()
        var lidShut: Double?
        var shutTime = 0.0
        while shutTime < 1, lidShut == nil {
            closing.step(frame)
            shutTime += frame
            if closing.openness <= 0.02 { lidShut = shutTime }
        }
        let caseGone = timeTo(0, from: 1, target: -0.06, stiffness: 380, damping: 34)
        XCTAssertNotNil(lidShut)
        XCTAssertLessThan(lidShut ?? 9, caseGone, "the lid must be shut before the box is gone")
    }

    func testOpennessIsClampedToTheAnglesWeSupport() {
        XCTAssertEqual(CompassLid(metrics: metrics, openness: -3).openness, 0)
        XCTAssertEqual(CompassLid(metrics: metrics, openness: 9).openness, 1)
    }

    /// The gate that stops a fast summon-and-click from firing a slice the user never saw.
    func testCardOnlyRevealsOnceTheLidHasClearedIt() {
        XCTAssertFalse(CompassLid(metrics: metrics, openness: 0.2).revealsCard)
        XCTAssertFalse(CompassLid(metrics: metrics, openness: 0.5).revealsCard)
        XCTAssertTrue(CompassLid(metrics: metrics, openness: 1).revealsCard)
    }

    // MARK: The pan

    /// The lid is a shallow pan, not a plate: every dimension of its mesh has to nest.
    func testTheLidIsAPanWithAWallAFloorAndACover() {
        XCTAssertGreaterThan(metrics.lidDepth, 0)
        XCTAssertLessThan(metrics.lidFloorRadius, metrics.lidRadius, "the wall has thickness")
        XCTAssertLessThan(metrics.lidCoverRadius, metrics.lidRadius, "the shoulder rolls inward")
        XCTAssertGreaterThan(metrics.lidFloorHeight, 0)
        XCTAssertLessThan(metrics.lidFloorHeight, metrics.lidDepth, "the plate is under the cover")
        XCTAssertGreaterThan(metrics.lidShoulderHeight, 0)
        XCTAssertLessThan(metrics.lidShoulderHeight, metrics.lidDepth, "the shoulder is above the straight wall")
        XCTAssertGreaterThan(metrics.lidFloorRadius, metrics.cardRadius,
                             "the engraved plate is wide enough to cover the card it closes over")
    }

    /// A pan proportioned like a real one: shallow against its own diameter, and not a plate.
    func testTheLidIsShallowButNotPaperThin() {
        let ratio = metrics.lidDepth / (metrics.lidRadius * 2)
        XCTAssertGreaterThan(ratio, 0.03, "thinner than this is the flat disc this replaced")
        XCTAssertLessThan(ratio, 0.12, "deeper than this is a tin, not a lid")
    }

    /// The shut lid's rim rests on the case's crest, and the hinge pin is at that height: the lid
    /// is *on* the case, not floating a hair above it or sunk into it.
    func testTheShutLidRestsOnTheCasesCrest() {
        let lid = CompassLid(metrics: metrics, openness: 0)
        XCTAssertEqual(lid.hingeZ, metrics.cardDepth, accuracy: 1e-9)
        XCTAssertEqual(lid.point(radius: 50, angle: 1).z, lid.hingeZ, accuracy: 1e-9)
        XCTAssertEqual(lid.point(radius: 50, angle: 1, height: metrics.lidDepth).z,
                       lid.hingeZ + metrics.lidDepth, accuracy: 1e-9)
    }

    /// Directions turn with the lid, which is what lets a renderer light it: the cover's normal
    /// points at the viewer when shut, straight up the screen when the lid is vertical, and away
    /// from the viewer when it is open, so the *inside* is what faces the camera.
    func testNormalsTurnWithTheLid() {
        let up = Point3D(x: 0, y: 0, z: 1)
        let shut = CompassLid(metrics: metrics, openness: 0).swingDirection(up)
        XCTAssertEqual(shut.z, 1, accuracy: 1e-9)

        let vertical = CompassLid(metrics: metrics, openness: (.pi / 2) / CompassMetrics.lidOpenAngle)
            .swingDirection(up)
        XCTAssertEqual(vertical.y, -1, accuracy: 1e-9, "standing up, the cover faces up the screen")
        XCTAssertEqual(vertical.z, 0, accuracy: 1e-9)

        let open = CompassLid(metrics: metrics, openness: 1).swingDirection(up)
        XCTAssertLessThan(open.z, 0, "open, the cover faces away from the viewer and the inside faces them")
        XCTAssertEqual(open.x * open.x + open.y * open.y + open.z * open.z, 1, accuracy: 1e-9,
                       "a rotation keeps a direction a unit length")
    }

    /// The pan has depth, so its highest point is the cover's edge. A reach that measured the rim
    /// only would put the open lid's top above the layout's margin, which is how the old flat
    /// disc used to be clipped by the top of the screen.
    func testTheReachCountsTheCoverNotJustTheRim() {
        let camera = CompassCamera(eyeDistance: metrics.cardRadius * RadialTilt.eyeDistanceRatio)
        let lid = CompassLid(metrics: metrics, openness: 1)
        var rimOnly: CGFloat = 0
        for step in 0...48 {
            let angle = CGFloat(step) / 48 * 2 * .pi
            let point = camera.project(lid.swing(lid.point(radius: metrics.lidRadius, angle: angle))).point
            rimOnly = max(rimOnly, -point.y)
        }
        XCTAssertGreaterThan(metrics.lidReach(), rimOnly, "the cover's edge stands higher than the rim")
        XCTAssertLessThan(metrics.lidReach(), rimOnly * 1.2, "but only by the depth of the pan")
    }
}

final class LidHingeTests: XCTestCase {

    private let frame = 1.0 / 120

    private struct Flight {
        var clearedCard: Double?
        var firstImpact: (time: Double, speed: Double)?
        /// How far short of the stop the lid fell back after its first landing, in radians.
        var rebound = 0.0
        var restedAt: Double?
        var lowest = Double.infinity
        var highest = -Double.infinity
    }

    /// Runs `hinge` forward and records what it did.
    private func fly(_ hinge: inout LidHinge, seconds: Double = 1.5) -> Flight {
        var flight = Flight()
        var time = 0.0
        while time < seconds {
            hinge.step(frame)
            time += frame
            flight.lowest = min(flight.lowest, hinge.angle)
            flight.highest = max(flight.highest, hinge.angle)
            if flight.clearedCard == nil, hinge.openness > 0.55 { flight.clearedCard = time }
            if flight.firstImpact == nil, hinge.impact > 0 { flight.firstImpact = (time, hinge.impact) }
            if flight.firstImpact != nil { flight.rebound = max(flight.rebound, hinge.stop - hinge.angle) }
            if flight.restedAt == nil, hinge.mode == .resting { flight.restedAt = time }
        }
        return flight
    }

    func testTheDefaultStopIsTheMetricsOpenAngle() {
        XCTAssertEqual(LidHinge.defaultStop, Double(CompassMetrics.lidOpenAngle), accuracy: 1e-12)
    }

    func testItStartsShutAndStill() {
        let hinge = LidHinge()
        XCTAssertEqual(hinge.angle, 0)
        XCTAssertEqual(hinge.openness, 0)
        XCTAssertFalse(hinge.isMoving)
    }

    /// Nothing is in flight until it is asked to move, so an idle compass costs no frames.
    func testARestingHingeDoesNotMove() {
        var hinge = LidHinge()
        for _ in 0..<60 { hinge.step(frame) }
        XCTAssertEqual(hinge.angle, 0)
        XCTAssertEqual(hinge.impact, 0)
    }

    /// The gesture, in numbers: clears the card in about 135ms, falls onto its stop at about 290ms
    /// at a few radians a second, gives one small bounce and is at rest by about half a second.
    /// The bounds are wide enough for tuning and narrow enough that a spring-like creep (no
    /// landing) or a rattle (many bounces) fails.
    func testOpeningIsOneWeightyGesture() {
        var hinge = LidHinge()
        hinge.release()
        XCTAssertTrue(hinge.isMoving)
        let flight = fly(&hinge)

        XCTAssertEqual(hinge.angle, hinge.stop, "it ends on the stop")
        XCTAssertEqual(hinge.mode, .resting)

        let cleared = flight.clearedCard ?? 9
        XCTAssertGreaterThan(cleared, 0.08)
        XCTAssertLessThan(cleared, 0.20)

        guard let impact = flight.firstImpact else { return XCTFail("the lid never landed on its stop") }
        XCTAssertGreaterThan(impact.time, 0.22, "it should swing, not snap")
        XCTAssertLessThan(impact.time, 0.40)
        XCTAssertGreaterThan(impact.speed, 3, "it lands with weight")
        XCTAssertLessThan(impact.speed, 9, "but does not slam")

        XCTAssertGreaterThan(flight.rebound, 0.02, "there is a little bounce to see")
        XCTAssertLessThan(flight.rebound, 0.25, "and it is a little one")
        XCTAssertLessThan(flight.restedAt ?? 9, 0.8, "and it settles")
    }

    /// The point of a hinge stop: the lid never goes through it, and never through the case.
    func testItNeverLeavesItsTravel() {
        var hinge = LidHinge()
        hinge.release()
        var flight = fly(&hinge)
        XCTAssertLessThanOrEqual(flight.highest, hinge.stop)
        XCTAssertGreaterThanOrEqual(flight.lowest, 0)
        hinge.shut()
        flight = fly(&hinge)
        XCTAssertLessThanOrEqual(flight.highest, hinge.stop)
        XCTAssertGreaterThanOrEqual(flight.lowest, 0)
    }

    /// A landing is reported for exactly one step, and only a real landing counts: resting contact
    /// against the stop (gravity pressing the lid onto it) is not an impact.
    func testImpactIsReportedOnlyForRealLandings() {
        var hinge = LidHinge()
        hinge.release()
        var landings = 0
        var time = 0.0
        while time < 1.5 {
            hinge.step(frame)
            time += frame
            if hinge.impact > 0 { landings += 1 }
        }
        XCTAssertGreaterThanOrEqual(landings, 1)
        XCTAssertLessThanOrEqual(landings, 3, "a bounce or two, not a rattle")
        XCTAssertEqual(hinge.impact, 0, "and nothing once it is at rest")
    }

    /// The failure this model had to be built around: a lid that is released when it is partly open
    /// and stalls before vertical falls back shut under gravity, so the compass would open and
    /// then close on its own. Whatever it was doing, a release must end with the lid on the open stop.
    /// The cases are real reversals: opened for a while, pushed shut for a while, then released.
    func testAReleaseAlwaysEndsOpen() {
        for openFrames in stride(from: 0, to: 80, by: 3) {
            for closeFrames in stride(from: 0, to: 40, by: 3) {
                var hinge = LidHinge()
                hinge.release()
                for _ in 0..<openFrames { hinge.step(frame) }
                hinge.shut()
                for _ in 0..<closeFrames { hinge.step(frame) }
                hinge.release()
                _ = fly(&hinge)
                XCTAssertEqual(hinge.angle, hinge.stop,
                               "stalled after \(openFrames) frames open, \(closeFrames) frames closing")
                XCTAssertEqual(hinge.mode, .resting)
            }
        }
    }

    /// A hard launch must not bounce the lid back below vertical, where gravity would shut it.
    func testTheReboundNeverCarriesItBackBelowVertical() {
        for openFrames in stride(from: 0, to: 40, by: 2) {
            var hinge = LidHinge()
            hinge.release()
            for _ in 0..<openFrames { hinge.step(frame) }
            hinge.shut()
            hinge.step(frame)
            hinge.release()
            var time = 0.0
            var afterLanding = false
            while time < 1.5 {
                hinge.step(frame)
                time += frame
                if hinge.impact > 0 { afterLanding = true }
                if afterLanding {
                    XCTAssertGreaterThan(hinge.angle, .pi / 2 + 0.1,
                                         "after landing it must stay clear of vertical")
                }
            }
        }
    }

    /// Closing is quick and ends on the case with a small clack.
    func testClosingIsQuickAndEndsShut() {
        var hinge = LidHinge()
        hinge.release()
        _ = fly(&hinge)
        hinge.shut()
        let flight = fly(&hinge, seconds: 1)
        XCTAssertEqual(hinge.angle, 0)
        XCTAssertEqual(hinge.mode, .resting)
        XCTAssertLessThan(flight.restedAt ?? 9, 0.35, "a hand shuts a lid quickly")
        XCTAssertGreaterThanOrEqual(flight.lowest, 0)
    }

    /// Shutting a lid that is already shut costs nothing and leaves it at rest.
    func testShuttingAShutLidIsANoOp() {
        var hinge = LidHinge()
        hinge.shut()
        for _ in 0..<10 { hinge.step(frame) }
        XCTAssertEqual(hinge.angle, 0)
        XCTAssertEqual(hinge.mode, .resting)
    }

    func testSnapShutClearsEverythingInFlight() {
        var hinge = LidHinge()
        hinge.release()
        for _ in 0..<12 { hinge.step(frame) }
        hinge.snapShut()
        XCTAssertEqual(hinge.angle, 0)
        XCTAssertEqual(hinge.velocity, 0)
        XCTAssertEqual(hinge.mode, .resting)
        XCTAssertFalse(hinge.isMoving)
    }

    /// The landing time may not depend on the frame rate: a 30Hz stall and a 240Hz display have to
    /// land the lid at the same moment, to within a frame.
    func testLandingTimeDoesNotDependOnTheFrameRate() {
        func landing(at step: Double) -> Double {
            var hinge = LidHinge()
            hinge.release()
            var time = 0.0
            while time < 1 {
                hinge.step(step)
                time += step
                if hinge.impact > 0 { return time }
            }
            return time
        }
        let fast = landing(at: 1.0 / 240)
        XCTAssertEqual(landing(at: 1.0 / 60), fast, accuracy: 0.03)
        XCTAssertEqual(landing(at: 1.0 / 30), fast, accuracy: 0.04)
    }

    func testAHugeStepCannotTunnelThroughTheStop() {
        var hinge = LidHinge()
        hinge.release()
        hinge.step(10)
        XCTAssertLessThanOrEqual(hinge.angle, hinge.stop)
        XCTAssertGreaterThanOrEqual(hinge.angle, 0)
    }
}
