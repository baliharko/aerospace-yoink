import XCTest
@testable import YoinkLib

final class ConfigTests: XCTestCase {

    // MARK: - Defaults

    func testDefaultValues() {
        let config = Config()
        XCTAssertEqual(config.fadeIn, 0.1)
        XCTAssertEqual(config.fadeOut, 0.08)
        XCTAssertTrue(config.focusAfterYoink)
    }

    // MARK: - Valid input

    func testParsesAllKeys() {
        var config = Config()
        config.parse("""
            fade-in = 0.2
            fade-out = 0.15
            focus-after-yoink = false
            """)
        XCTAssertEqual(config.fadeIn, 0.2)
        XCTAssertEqual(config.fadeOut, 0.15)
        XCTAssertFalse(config.focusAfterYoink)
    }

    func testParsesPartialConfig() {
        var config = Config()
        config.parse("fade-in = 0.5")
        XCTAssertEqual(config.fadeIn, 0.5)
        XCTAssertEqual(config.fadeOut, 0.08)
        XCTAssertTrue(config.focusAfterYoink)
    }

    func testParsesZeroValues() {
        var config = Config()
        config.parse("""
            fade-in = 0
            fade-out = 0.0
            """)
        XCTAssertEqual(config.fadeIn, 0)
        XCTAssertEqual(config.fadeOut, 0)
    }

    func testFocusAfterYoinkTrue() {
        var config = Config()
        config.focusAfterYoink = false
        config.parse("focus-after-yoink = true")
        XCTAssertTrue(config.focusAfterYoink)
    }

    // MARK: - Comments and whitespace

    func testIgnoresComments() {
        var config = Config()
        config.parse("""
            # This is a comment
            fade-in = 0.3
            # Another comment
            """)
        XCTAssertEqual(config.fadeIn, 0.3)
    }

    func testIgnoresBlankLines() {
        var config = Config()
        config.parse("""

            fade-in = 0.3

            fade-out = 0.2

            """)
        XCTAssertEqual(config.fadeIn, 0.3)
        XCTAssertEqual(config.fadeOut, 0.2)
    }

    func testHandlesExtraWhitespace() {
        var config = Config()
        config.parse("  fade-in   =   0.4  ")
        XCTAssertEqual(config.fadeIn, 0.4)
    }

    func testEmptyFileReturnsDefaults() {
        var config = Config()
        config.parse("")
        XCTAssertEqual(config.fadeIn, 0.1)
        XCTAssertEqual(config.fadeOut, 0.08)
        XCTAssertTrue(config.focusAfterYoink)
    }

    func testCommentOnlyFileReturnsDefaults() {
        var config = Config()
        config.parse("""
            # just comments
            # nothing else
            """)
        XCTAssertEqual(config.fadeIn, 0.1)
    }

    // MARK: - Invalid input (should keep defaults)

    func testNegativeNumberKeepsDefault() {
        var config = Config()
        config.parse("fade-in = -0.5")
        XCTAssertEqual(config.fadeIn, 0.1)
    }

    func testNonNumericFadeKeepsDefault() {
        var config = Config()
        config.parse("fade-in = abc")
        XCTAssertEqual(config.fadeIn, 0.1)
    }

    func testInvalidBoolKeepsDefault() {
        var config = Config()
        config.parse("focus-after-yoink = yes")
        XCTAssertTrue(config.focusAfterYoink)
    }

    func testMissingEqualsSignSkipsLine() {
        var config = Config()
        config.parse("""
            this line has no equals
            fade-in = 0.3
            """)
        XCTAssertEqual(config.fadeIn, 0.3)
    }

    func testUnknownKeySkipsLine() {
        var config = Config()
        config.parse("""
            unknown-key = 42
            fade-in = 0.3
            """)
        XCTAssertEqual(config.fadeIn, 0.3)
    }

    func testInvalidValueDoesNotCorruptOtherKeys() {
        var config = Config()
        config.parse("""
            fade-in = not-a-number
            fade-out = 0.2
            focus-after-yoink = maybe
            """)
        XCTAssertEqual(config.fadeIn, 0.1)
        XCTAssertEqual(config.fadeOut, 0.2)
        XCTAssertTrue(config.focusAfterYoink)
    }

    // MARK: - File resolution

    func testLoadReturnsDefaultsWhenNoFile() {
        let config = Config.load()
        XCTAssertGreaterThanOrEqual(config.fadeIn, 0)
        XCTAssertGreaterThanOrEqual(config.fadeOut, 0)
    }
}
