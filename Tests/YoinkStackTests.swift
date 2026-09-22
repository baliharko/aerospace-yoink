import XCTest
@testable import YoinkLib

final class YoinkStackTests: RuntimeDirTestCase {

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

        let stack = YoinkStack()
        stack.push(windowId: 1, originWorkspace: "2", destinationWorkspace: "1")
        stack.push(windowId: 3, originWorkspace: "4", destinationWorkspace: "1")
        stack.save()
        defer { unlink(RuntimePaths.stackFile) }

        let loaded = YoinkStack()
        loaded.load()
        XCTAssertEqual(loaded.entries.count, 2)
        XCTAssertEqual(loaded.entries[0].windowId, 3)
        XCTAssertEqual(loaded.entries[1].windowId, 1)
    }

    func testStackIsNotStoredInPidFile() throws {
        // The daemon deletes its PID file on a clean exit; the stack has to
        // live elsewhere to survive a restart.
        try RuntimePaths.ensureDirectory()
        unlink(RuntimePaths.pidFile)

        let stack = YoinkStack()
        stack.push(windowId: 1, originWorkspace: "2", destinationWorkspace: "1")
        stack.save()
        defer { unlink(RuntimePaths.stackFile) }

        XCTAssertFalse(FileManager.default.fileExists(atPath: RuntimePaths.pidFile))
        XCTAssertTrue(FileManager.default.fileExists(atPath: RuntimePaths.stackFile))
    }

    func testLoadIgnoresStackFromAnotherSession() throws {
        // Window IDs are reused after a reboot or re-login, so a stack from
        // another session would point at unrelated windows.
        try RuntimePaths.ensureDirectory()

        let stack = YoinkStack(session: "old-session")
        stack.push(windowId: 1, originWorkspace: "2", destinationWorkspace: "1")
        stack.save()
        defer { unlink(RuntimePaths.stackFile) }

        let sameSession = YoinkStack(session: "old-session")
        sameSession.load()
        XCTAssertEqual(sameSession.entries.count, 1)

        let newSession = YoinkStack(session: "new-session")
        newSession.load()
        XCTAssertTrue(newSession.isEmpty)
    }

    func testSavingEmptyStackRemovesFile() throws {
        try RuntimePaths.ensureDirectory()

        let stack = YoinkStack()
        stack.push(windowId: 1, originWorkspace: "2", destinationWorkspace: "1")
        stack.save()
        XCTAssertTrue(FileManager.default.fileExists(atPath: RuntimePaths.stackFile))

        _ = stack.pop()
        stack.save()
        XCTAssertFalse(FileManager.default.fileExists(atPath: RuntimePaths.stackFile))
    }

    func testLoadFromCorruptFileDoesNotRestore() throws {
        try RuntimePaths.ensureDirectory()
        try "not-a-session\n1|2|1".write(toFile: RuntimePaths.stackFile, atomically: true, encoding: .utf8)
        defer { unlink(RuntimePaths.stackFile) }

        let stack = YoinkStack()
        stack.load()
        XCTAssertTrue(stack.isEmpty)
    }

    func testLoadFromNonExistentFileIsNoOp() {
        unlink(RuntimePaths.stackFile)
        let stack = YoinkStack()
        stack.load()
        XCTAssertTrue(stack.isEmpty)
    }
}
