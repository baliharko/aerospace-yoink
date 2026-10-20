import XCTest
import AppKit
@testable import YoinkLib

final class AerospaceParsingTests: XCTestCase {

    // MARK: - parseWindowList

    func testParsesValidWindowList() {
        let raw = """
            [
              {"window-id": 42, "app-pid": 100, "workspace": "2", "app-name": "Safari", "window-title": "Apple - Start"},
              {"window-id": 99, "app-pid": 200, "workspace": "3", "app-name": "Terminal", "window-title": "~/projects"}
            ]
            """
        let windows = Aerospace.parseWindowList(raw, excluding: "1")
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].id, 42)
        XCTAssertEqual(windows[0].workspace, "2")
        XCTAssertEqual(windows[0].appName, "Safari")
        XCTAssertEqual(windows[0].title, "Apple - Start")
        XCTAssertEqual(windows[1].id, 99)
        XCTAssertEqual(windows[1].appName, "Terminal")
    }

    func testExcludesCurrentWorkspace() {
        let raw = """
            [
              {"window-id": 42, "app-pid": 100, "workspace": "1", "app-name": "Safari", "window-title": "Page"},
              {"window-id": 99, "app-pid": 200, "workspace": "2", "app-name": "Terminal", "window-title": "Shell"}
            ]
            """
        let windows = Aerospace.parseWindowList(raw, excluding: "1")
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].id, 99)
    }

    func testEmptyInputReturnsEmpty() {
        XCTAssertTrue(Aerospace.parseWindowList("", excluding: "1").isEmpty)
        XCTAssertTrue(Aerospace.parseWindowList("[]", excluding: "1").isEmpty)
    }

    func testMalformedInputReturnsEmpty() {
        XCTAssertTrue(Aerospace.parseWindowList("not json", excluding: "1").isEmpty)
        let wrongType = #"[{"window-id": "abc", "app-pid": 1, "workspace": "2", "app-name": "A", "window-title": "B"}]"#
        XCTAssertTrue(Aerospace.parseWindowList(wrongType, excluding: "1").isEmpty)
    }

    func testTitleWithPipesAndNewlinesSurvives() {
        // Both broke the old "|"-delimited, line-based format.
        let raw = #"[{"window-id": 42, "app-pid": 1, "workspace": "2", "app-name": "Safari", "window-title": "Page | Tab\nLine 2"}]"#
        let windows = Aerospace.parseWindowList(raw, excluding: "1")
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].title, "Page | Tab\nLine 2")
    }

    func testIconsAreMatchedByPid() {
        // Two apps with the same display name must keep their own icons.
        let first = NSImage(size: NSSize(width: 16, height: 16))
        let second = NSImage(size: NSSize(width: 16, height: 16))
        let raw = """
            [
              {"window-id": 1, "app-pid": 10, "workspace": "2", "app-name": "Code", "window-title": "a"},
              {"window-id": 2, "app-pid": 20, "workspace": "2", "app-name": "Code", "window-title": "b"}
            ]
            """
        let windows = Aerospace.parseWindowList(raw, excluding: "1", iconCache: [10: first, 20: second])
        XCTAssertTrue(windows[0].icon === first)
        XCTAssertTrue(windows[1].icon === second)
    }

    func testUnknownPidFallsBackToDefaultIcon() {
        let fallback = NSImage(size: NSSize(width: 16, height: 16))
        let raw = #"[{"window-id": 42, "app-pid": 999, "workspace": "2", "app-name": "Safari", "window-title": "Page"}]"#
        let windows = Aerospace.parseWindowList(raw, excluding: "1", iconCache: [:], defaultIcon: fallback)
        XCTAssertTrue(windows[0].icon === fallback)
    }

    // MARK: - parseFocusedWorkspace

    func testParsesFocusedWorkspaceAndScreen() {
        let (workspace, screenIndex) = Aerospace.parseFocusedWorkspace("2|web")
        XCTAssertEqual(workspace, "web")
        XCTAssertEqual(screenIndex, 1, "AeroSpace's 1-based screen ID maps to a 0-based NSScreen.screens index")
    }

    func testFocusedWorkspaceNameMayContainPipe() {
        XCTAssertEqual(Aerospace.parseFocusedWorkspace("1|a|b").workspace, "a|b")
    }

    func testFailedFocusedWorkspaceQuery() {
        let (workspace, screenIndex) = Aerospace.parseFocusedWorkspace("")
        XCTAssertEqual(workspace, "", "empty workspace is how activate() detects AeroSpace being down")
        XCTAssertNil(screenIndex)
    }

    // MARK: - parseWindowLocations

    func testParsesValidLocations() {
        let raw = """
            42|1
            99|2
            """
        let locs = Aerospace.parseWindowLocations(raw)
        XCTAssertEqual(locs.count, 2)
        XCTAssertEqual(locs[0].windowId, 42)
        XCTAssertEqual(locs[0].workspace, "1")
        XCTAssertEqual(locs[1].windowId, 99)
        XCTAssertEqual(locs[1].workspace, "2")
    }

    func testEmptyLocationInputReturnsEmpty() {
        XCTAssertTrue(Aerospace.parseWindowLocations("").isEmpty)
    }

    func testMalformedLocationLineSkipped() {
        let raw = """
            42|1
            bad-line
            99|2
            """
        let locs = Aerospace.parseWindowLocations(raw)
        XCTAssertEqual(locs.count, 2)
    }
}
