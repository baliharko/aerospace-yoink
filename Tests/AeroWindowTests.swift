import XCTest
import AppKit
@testable import YoinkLib

final class AeroWindowTests: XCTestCase {

    private func window(appName: String = "Safari", title: String = "Apple", workspace: String = "1") -> AeroWindow {
        AeroWindow(id: 1, workspace: workspace, appName: appName, title: title, icon: NSImage())
    }

    /// Mirrors the call site: the query is split into terms once, then matched.
    private func matches(_ w: AeroWindow, _ query: String) -> Bool {
        w.matches(terms: AeroWindow.searchTerms(query))
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

    // MARK: - Multi-word queries

    func testEveryTermMustMatch() {
        let chrome = window(appName: "Google Chrome", title: "baliharko/aerospace-yoink · GitHub")
        XCTAssertTrue(matches(chrome, "chrome github"))
        XCTAssertFalse(matches(chrome, "chrome gitlab"))
    }

    func testTermOrderDoesNotMatter() {
        let chrome = window(appName: "Google Chrome", title: "Pull requests · GitHub")
        XCTAssertTrue(matches(chrome, "github chrome"))
    }

    func testTermsCanMatchDifferentFields() {
        XCTAssertTrue(matches(window(appName: "Code", title: "main.swift", workspace: "3"), "code 3"))
    }

    func testExtraWhitespaceIsIgnored() {
        XCTAssertTrue(matches(window(appName: "Safari", title: "Apple"), "  safari   apple "))
        XCTAssertTrue(matches(window(), "   "), "a whitespace-only query matches everything")
    }
}
