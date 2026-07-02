import XCTest
import AppKit
@testable import YoinkLib

final class AeroWindowTests: XCTestCase {

    private func window(appName: String = "Safari", title: String = "Apple", workspace: String = "1") -> AeroWindow {
        AeroWindow(id: 1, workspace: workspace, appName: appName, title: title, icon: NSImage())
    }

    /// Mirrors the call site: the query is lowercased once, then matched.
    private func matches(_ w: AeroWindow, _ query: String) -> Bool {
        w.matches(lowercasedQuery: query.lowercased())
    }

    func testEmptyQueryMatchesEverything() {
        XCTAssertTrue(matches(window(), ""))
    }

    func testMatchesAppNameCaseInsensitive() {
        XCTAssertTrue(matches(window(appName: "Safari"), "safari"))
        XCTAssertTrue(matches(window(appName: "Safari"), "SAFARI"))
    }

    func testMatchesTitleCaseInsensitive() {
        XCTAssertTrue(matches(window(title: "Inbox - Mail"), "inbox"))
        XCTAssertTrue(matches(window(title: "Inbox - Mail"), "MAIL"))
    }

    func testMatchesWorkspaceCaseInsensitive() {
        XCTAssertTrue(matches(window(workspace: "Dev"), "dev"))
        XCTAssertTrue(matches(window(workspace: "Dev"), "DEV"))
    }

    func testPartialSubstringMatches() {
        XCTAssertTrue(matches(window(appName: "Visual Studio Code"), "studio"))
    }

    func testNoMatchReturnsFalse() {
        XCTAssertFalse(matches(window(appName: "Safari", title: "Apple", workspace: "1"), "firefox"))
    }

    func testMatchesUnicodeCharacters() {
        XCTAssertTrue(matches(window(title: "日本語ページ"), "日本"))
        XCTAssertTrue(matches(window(appName: "Ünïcödé App"), "ünïcödé"))
    }

    func testMatchesWithSpecialCharacters() {
        XCTAssertTrue(matches(window(title: "file.txt - Editor"), "file.txt"))
        XCTAssertTrue(matches(window(title: "project (main)"), "(main)"))
    }
}
