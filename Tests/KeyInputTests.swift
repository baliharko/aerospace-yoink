import XCTest
@testable import YoinkLib

final class KeyInputTests: XCTestCase {

    func testPrintableCharactersOpenSearch() {
        for chars in ["a", "Z", "1", " ", "-", "é", "ß", "日"] {
            XCTAssertTrue(KeyCode.opensSearch(chars), "'\(chars)' should open the filter")
        }
    }

    /// These used to reveal an empty filter field, after which Escape closed
    /// the whole panel instead of just the filter.
    func testNavigationAndControlKeysDoNotOpenSearch() {
        let keys: [String: String] = [
            "left arrow": "\u{F702}",
            "right arrow": "\u{F703}",
            "F5": "\u{F708}",
            "forward delete": "\u{F728}",
            "home": "\u{F729}",
            "page down": "\u{F72D}",
            "tab": "\t",
            "backspace": "\u{7F}",
            "dead key (no characters yet)": "",
        ]
        for (name, chars) in keys {
            XCTAssertFalse(KeyCode.opensSearch(chars), "\(name) should not open the filter")
        }
    }

    func testControlNavigationBindings() {
        XCTAssertEqual(KeyCode.controlNavigation["n"], 1)
        XCTAssertEqual(KeyCode.controlNavigation["j"], 1)
        XCTAssertEqual(KeyCode.controlNavigation["p"], -1)
        XCTAssertEqual(KeyCode.controlNavigation["k"], -1)
        XCTAssertNil(KeyCode.controlNavigation["a"])
    }
}
