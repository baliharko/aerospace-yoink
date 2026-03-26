import XCTest
@testable import YoinkLib

final class CLIArgsTests: XCTestCase {

    func testNoArgs() {
        let args = CLIArgs(arguments: [])
        XCTAssertFalse(args.isDaemon)
        XCTAssertFalse(args.isYeet)
        XCTAssertFalse(args.noFocus)
    }

    func testDaemonFlag() {
        let args = CLIArgs(arguments: ["--daemon"])
        XCTAssertTrue(args.isDaemon)
        XCTAssertFalse(args.isYeet)
        XCTAssertFalse(args.noFocus)
    }

    func testYeetFlag() {
        let args = CLIArgs(arguments: ["--yeet"])
        XCTAssertTrue(args.isYeet)
        XCTAssertFalse(args.isDaemon)
    }

    func testNoFocusFlag() {
        let args = CLIArgs(arguments: ["--no-focus"])
        XCTAssertTrue(args.noFocus)
    }

    func testMultipleFlags() {
        let args = CLIArgs(arguments: ["--daemon", "--no-focus"])
        XCTAssertTrue(args.isDaemon)
        XCTAssertTrue(args.noFocus)
        XCTAssertFalse(args.isYeet)
    }

    func testUnknownFlagsIgnored() {
        let args = CLIArgs(arguments: ["--unknown", "--daemon", "positional"])
        XCTAssertTrue(args.isDaemon)
        XCTAssertFalse(args.isYeet)
    }

    func testBinaryNameIgnored() {
        let args = CLIArgs(arguments: ["/usr/local/bin/yoink", "--yeet"])
        XCTAssertTrue(args.isYeet)
        XCTAssertFalse(args.isDaemon)
    }

    func testEquatable() {
        let a = CLIArgs(arguments: ["--yeet", "--no-focus"])
        let b = CLIArgs(arguments: ["--no-focus", "--yeet"])
        XCTAssertEqual(a, b)
    }
}
