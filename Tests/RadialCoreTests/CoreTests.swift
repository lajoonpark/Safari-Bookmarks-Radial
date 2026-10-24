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

    func testMoveReorders() {
        let store = BookmarkStore(bookmarks: (0..<3).map {
            Bookmark(title: "\($0)", url: "https://s\($0).com")
        })
        store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(store.bookmarks.map(\.title), ["2", "0", "1"])
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
