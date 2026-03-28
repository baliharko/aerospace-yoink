import XCTest
import AppKit
@testable import YoinkLib

final class AeroWindowTests: XCTestCase {

    private func window(appName: String = "Safari", title: String = "Apple", workspace: String = "1") -> AeroWindow {
        AeroWindow(id: 1, workspace: workspace, appName: appName, title: title, icon: NSImage())
    }

    func testEmptyQueryMatchesEverything() {
        XCTAssertTrue(window().matches(""))
    }

    func testMatchesAppNameCaseInsensitive() {
        XCTAssertTrue(window(appName: "Safari").matches("safari"))
        XCTAssertTrue(window(appName: "Safari").matches("SAFARI"))
    }

    func testMatchesTitleCaseInsensitive() {
        XCTAssertTrue(window(title: "Inbox - Mail").matches("inbox"))
        XCTAssertTrue(window(title: "Inbox - Mail").matches("MAIL"))
    }

    func testMatchesWorkspaceCaseInsensitive() {
        XCTAssertTrue(window(workspace: "Dev").matches("dev"))
        XCTAssertTrue(window(workspace: "Dev").matches("DEV"))
    }

    func testPartialSubstringMatches() {
        XCTAssertTrue(window(appName: "Visual Studio Code").matches("studio"))
    }

    func testNoMatchReturnsFalse() {
        XCTAssertFalse(window(appName: "Safari", title: "Apple", workspace: "1").matches("firefox"))
    }

    func testMatchesUnicodeCharacters() {
        XCTAssertTrue(window(title: "日本語ページ").matches("日本"))
        XCTAssertTrue(window(appName: "Ünïcödé App").matches("ünïcödé"))
    }

    func testMatchesWithSpecialCharacters() {
        XCTAssertTrue(window(title: "file.txt - Editor").matches("file.txt"))
        XCTAssertTrue(window(title: "project (main)").matches("(main)"))
    }
}
