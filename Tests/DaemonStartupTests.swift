import XCTest
@testable import YoinkLib

final class DaemonStartupTests: XCTestCase {

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
