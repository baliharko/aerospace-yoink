import XCTest
@testable import YoinkLib

final class DaemonStartupTests: RuntimeDirTestCase {

    // MARK: - Runtime directory

    func testEnsureDirectoryCreatesWithCorrectPermissions() throws {
        try RuntimePaths.ensureDirectory()

        let attrs = try FileManager.default.attributesOfItem(atPath: RuntimePaths.dir)
        let perms = (attrs[.posixPermissions] as? Int) ?? 0
        XCTAssertEqual(perms, 0o700, "Runtime directory should have 0700 permissions")
    }

    func testEnsureDirectoryIsIdempotent() throws {
        try RuntimePaths.ensureDirectory()
        try RuntimePaths.ensureDirectory() // should not throw on second call
    }

    // MARK: - PID file

    func testPidFileWriteAndRead() throws {
        try RuntimePaths.ensureDirectory()
        let pidFile = RuntimePaths.pidFile
        let pid = getpid()

        try "\(pid)".write(toFile: pidFile, atomically: true, encoding: .utf8)
        defer { unlink(pidFile) }

        let content = try String(contentsOfFile: pidFile, encoding: .utf8)
        XCTAssertEqual(content, "\(pid)")
    }

    func testPidFileIsInRuntimeDir() {
        XCTAssertTrue(RuntimePaths.pidFile.hasPrefix(RuntimePaths.dir))
    }

    func testSocketPathIsInRuntimeDir() {
        XCTAssertTrue(RuntimePaths.socketPath.hasPrefix(RuntimePaths.dir))
    }

    // MARK: - Daemon lock

    func testDaemonLockIsExclusive() throws {
        try RuntimePaths.ensureDirectory()
        let fd = try XCTUnwrap(try DaemonLock.acquire())
        // flock locks belong to the open file description, so a second open
        // in this same process contends just like a second launch would.
        XCTAssertNil(try DaemonLock.acquire())

        close(fd)
        let again = try XCTUnwrap(try DaemonLock.acquire(), "lock should be free once the holder closes it")
        close(again)
    }

    func testAcquireOrForwardTakesFreeLock() throws {
        try RuntimePaths.ensureDirectory()
        unlink(RuntimePaths.socketPath)
        guard case .daemon(let fd) = try DaemonLock.acquireOrForward(["--daemon"], timeout: 0.2) else {
            return XCTFail("a free lock should make us the daemon")
        }
        close(fd)
    }

    /// Losing the race to a launch that's still starting up: our args must
    /// reach it once its socket is bound.
    @MainActor func testAcquireOrForwardWaitsForStartingDaemon() throws {
        try RuntimePaths.ensureDirectory()
        unlink(RuntimePaths.socketPath)
        let holder = try XCTUnwrap(try DaemonLock.acquire())
        defer { close(holder) }

        let exp = expectation(description: "args arrive once the listener is up")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            _ = startSocketListener { args in
                if args == ["--yeet"] { exp.fulfill() }
            }
        }
        XCTAssertEqual(try DaemonLock.acquireOrForward(["--yeet"], timeout: 3), .forwarded)
        waitForExpectations(timeout: 3)
    }

    /// The holder can be a short-lived launch (e.g. `--yeet` with no daemon)
    /// that exits without becoming the daemon — we must take over, not give up.
    func testAcquireOrForwardTakesOverFromTransientHolder() throws {
        try RuntimePaths.ensureDirectory()
        unlink(RuntimePaths.socketPath)
        let holder = try XCTUnwrap(try DaemonLock.acquire())
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { close(holder) }

        guard case .daemon(let fd) = try DaemonLock.acquireOrForward(["--daemon"], timeout: 3) else {
            return XCTFail("should take the lock once the transient holder exits")
        }
        close(fd)
    }

    func testAcquireOrForwardTimesOut() throws {
        try RuntimePaths.ensureDirectory()
        unlink(RuntimePaths.socketPath)
        let holder = try XCTUnwrap(try DaemonLock.acquire())
        defer { close(holder) }
        XCTAssertEqual(try DaemonLock.acquireOrForward(["--yeet"], timeout: 0.2), .timedOut)
    }

    // MARK: - Socket listener startup

    @MainActor func testSocketListenerBindsSuccessfully() throws {
        try RuntimePaths.ensureDirectory()

        let started = startSocketListener { _ in }
        XCTAssertTrue(started, "Socket listener should start successfully")

        // Verify socket file exists
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: RuntimePaths.socketPath),
            "Socket file should exist after listener starts"
        )
    }

    // MARK: - Full startup sequence

    @MainActor func testDaemonStartupSequence() throws {
        // Simulate the daemon startup steps from main.swift
        // 1. Create runtime directory
        try RuntimePaths.ensureDirectory()

        // 2. Write PID file
        let pid = getpid()
        let pidFile = RuntimePaths.pidFile
        try "\(pid)".write(toFile: pidFile, atomically: true, encoding: .utf8)
        defer { unlink(pidFile) }

        // 3. Start socket listener
        let started = startSocketListener { _ in }
        XCTAssertTrue(started, "Socket listener should start")

        // 4. Verify all runtime files exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: pidFile))
        XCTAssertTrue(FileManager.default.fileExists(atPath: RuntimePaths.socketPath))

        // 5. Verify a client can connect and send args
        let sent = sendArgs(["--yeet"])
        XCTAssertTrue(sent, "Client should be able to connect to daemon socket")
    }
}
