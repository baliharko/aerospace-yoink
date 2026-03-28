import XCTest
import AppKit
@testable import YoinkLib

final class AerospaceParsingTests: XCTestCase {

    // MARK: - parseWindowList

    func testParsesValidWindowList() {
        let raw = """
            42|2|Safari|Apple - Start
            99|3|Terminal|~/projects
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
            42|1|Safari|Page
            99|2|Terminal|Shell
            """
        let windows = Aerospace.parseWindowList(raw, excluding: "1")
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].id, 99)
    }

    func testEmptyInputReturnsEmpty() {
        XCTAssertTrue(Aerospace.parseWindowList("", excluding: "1").isEmpty)
    }

    func testMalformedLineSkipped() {
        let raw = """
            42|2|Safari|Page
            not-a-valid-line
            99|3|Terminal|Shell
            """
        let windows = Aerospace.parseWindowList(raw, excluding: "1")
        XCTAssertEqual(windows.count, 2)
    }

    func testNonNumericIdSkipped() {
        let raw = "abc|2|Safari|Page"
        XCTAssertTrue(Aerospace.parseWindowList(raw, excluding: "1").isEmpty)
    }

    func testTitleContainingPipes() {
        // maxSplits: 3 means the title can contain pipe characters
        let raw = "42|2|Safari|Page | Tab | Extra"
        let windows = Aerospace.parseWindowList(raw, excluding: "1")
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].title, "Page | Tab | Extra")
    }

    func testWhitespaceTrimmed() {
        let raw = "  42  |  Dev  |  Safari  |  Some Title  "
        let windows = Aerospace.parseWindowList(raw, excluding: "1")
        XCTAssertEqual(windows[0].id, 42)
        XCTAssertEqual(windows[0].workspace, "Dev")
        XCTAssertEqual(windows[0].appName, "Safari")
        XCTAssertEqual(windows[0].title, "Some Title")
    }

    func testUsesIconCacheWhenAvailable() {
        let icon = NSImage(size: NSSize(width: 16, height: 16))
        let raw = "42|2|Safari|Page"
        let windows = Aerospace.parseWindowList(raw, excluding: "1", iconCache: ["Safari": icon])
        XCTAssertEqual(windows[0].icon, icon)
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
