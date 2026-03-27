import XCTest
@testable import YoinkLib

final class YoinkStackTests: XCTestCase {

    func testNewStackIsEmpty() {
        let stack = YoinkStack()
        XCTAssertTrue(stack.isEmpty)
        XCTAssertTrue(stack.entries.isEmpty)
    }

    func testPushAddsEntry() {
        let stack = YoinkStack()
        stack.push(windowId: 1, originWorkspace: "2", destinationWorkspace: "1")
        XCTAssertFalse(stack.isEmpty)
        XCTAssertEqual(stack.entries.count, 1)
        XCTAssertEqual(stack.entries[0].windowId, 1)
        XCTAssertEqual(stack.entries[0].originWorkspace, "2")
        XCTAssertEqual(stack.entries[0].destinationWorkspace, "1")
    }

    func testPushExistingMovesToTopAndUpdatesDestination() {
        let stack = YoinkStack()
        stack.push(windowId: 1, originWorkspace: "2", destinationWorkspace: "1")
        stack.push(windowId: 2, originWorkspace: "3", destinationWorkspace: "1")
        // Re-push window 1 with new destination
        stack.push(windowId: 1, originWorkspace: "ignored", destinationWorkspace: "4")

        XCTAssertEqual(stack.entries.count, 2)
        // Window 1 should be at top with preserved origin but updated destination
        XCTAssertEqual(stack.entries[0].windowId, 1)
        XCTAssertEqual(stack.entries[0].originWorkspace, "2")
        XCTAssertEqual(stack.entries[0].destinationWorkspace, "4")
    }

    func testPopReturnsFirstAndRemoves() {
        let stack = YoinkStack()
        stack.push(windowId: 1, originWorkspace: "2", destinationWorkspace: "1")
        stack.push(windowId: 2, originWorkspace: "3", destinationWorkspace: "1")

        let entry = stack.pop()
        XCTAssertEqual(entry?.windowId, 2)
        XCTAssertEqual(stack.entries.count, 1)
    }

    func testPopOnEmptyReturnsNil() {
        XCTAssertNil(YoinkStack().pop())
    }

    func testRemoveByWindowId() {
        let stack = YoinkStack()
        stack.push(windowId: 1, originWorkspace: "2", destinationWorkspace: "1")
        stack.push(windowId: 2, originWorkspace: "3", destinationWorkspace: "1")

        stack.remove(windowId: 1)
        XCTAssertEqual(stack.entries.count, 1)
        XCTAssertEqual(stack.entries[0].windowId, 2)
    }

    func testRemoveNonExistentIsNoOp() {
        let stack = YoinkStack()
        stack.push(windowId: 1, originWorkspace: "2", destinationWorkspace: "1")
        stack.remove(windowId: 99)
        XCTAssertEqual(stack.entries.count, 1)
    }

    func testSaveAndLoadRoundTrip() throws {
        try RuntimePaths.ensureDirectory()
        let pid = getpid()

        let stack = YoinkStack()
        stack.push(windowId: 1, originWorkspace: "2", destinationWorkspace: "1")
        stack.push(windowId: 3, originWorkspace: "4", destinationWorkspace: "1")
        stack.save(pid: pid)
        defer { unlink(RuntimePaths.pidFile) }

        let loaded = YoinkStack()
        loaded.load(pid: pid)
        XCTAssertEqual(loaded.entries.count, 2)
        XCTAssertEqual(loaded.entries[0].windowId, 3)
        XCTAssertEqual(loaded.entries[1].windowId, 1)
    }

    func testLoadWithMismatchedPidDoesNotRestore() throws {
        try RuntimePaths.ensureDirectory()
        let pid = getpid()

        let stack = YoinkStack()
        stack.push(windowId: 1, originWorkspace: "2", destinationWorkspace: "1")
        stack.save(pid: pid)
        defer { unlink(RuntimePaths.pidFile) }

        let loaded = YoinkStack()
        loaded.load(pid: pid + 1)
        XCTAssertTrue(loaded.isEmpty)
    }

    func testLoadFromNonExistentFileIsNoOp() {
        let stack = YoinkStack()
        stack.load(pid: 99999)
        XCTAssertTrue(stack.isEmpty)
    }
}
