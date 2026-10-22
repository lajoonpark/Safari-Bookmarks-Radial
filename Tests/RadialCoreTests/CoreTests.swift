import XCTest
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

    func testDefaultIsCommandR() {
        XCTAssertEqual(HotkeySpec.default.displayName, "⌘R")
        XCTAssertTrue(HotkeySpec.default.isValid)
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
        let conflict = HotkeyConflicts.conflict(for: .default)
        XCTAssertEqual(conflict?.owner, "Safari")
        XCTAssertEqual(conflict?.description, "reloads the page")
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
        let safer = HotkeyConflicts.saferAlternative(to: .default)
        XCTAssertEqual(safer, HotkeySpec(keyCode: 15, command: true, control: true))
        XCTAssertNil(HotkeyConflicts.conflict(for: safer))
    }

    func testSaferAlternativeNeverProducesInvalidHotkey() {
        let optionOnly = HotkeySpec(keyCode: 15, option: true)
        XCTAssertTrue(HotkeyConflicts.saferAlternative(to: optionOnly).isValid)
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
