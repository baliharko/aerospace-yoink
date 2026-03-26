import XCTest
@testable import YoinkLib

final class IPCTests: XCTestCase {

    // MARK: - Round-trip tests

    /// Verifies that multi-arg messages with null separators survive the round trip.
    @MainActor func testRoundTripMultipleArgs() {
        let (path, cleanup) = makeTestSocket()
        defer { cleanup() }

        let exp = expectation(description: "received args")
        nonisolated(unsafe) var receivedArgs: [String]?

        let source = startTestListener(path: path) { args in
            receivedArgs = args
            exp.fulfill()
        }
        defer { source?.cancel() }

        XCTAssertTrue(sendTestArgs(["--yeet", "--no-focus"], path: path))
        waitForExpectations(timeout: 2)
        XCTAssertEqual(receivedArgs, ["--yeet", "--no-focus"])
    }

    @MainActor func testRoundTripSingleArg() {
        let (path, cleanup) = makeTestSocket()
        defer { cleanup() }

        let exp = expectation(description: "received args")
        nonisolated(unsafe) var receivedArgs: [String]?

        let source = startTestListener(path: path) { args in
            receivedArgs = args
            exp.fulfill()
        }
        defer { source?.cancel() }

        XCTAssertTrue(sendTestArgs(["--daemon"], path: path))
        waitForExpectations(timeout: 2)
        XCTAssertEqual(receivedArgs, ["--daemon"])
    }

    func testSendEmptyArgsSucceeds() {
        // Empty args produce a zero-length message. write() sends nothing,
        // which is a valid no-op — the daemon simply ignores it.
        let (path, cleanup) = makeTestSocket()
        defer { cleanup() }

        let source = startTestListener(path: path) { _ in }
        defer { source?.cancel() }

        // Should still connect and return true (0 bytes written == 0 bytes requested)
        XCTAssertTrue(sendTestArgs([], path: path))
    }

    func testSendToNonexistentSocketFails() {
        XCTAssertFalse(sendTestArgs(["--yeet"], path: "/tmp/yoink-nonexistent-\(UUID()).sock"))
    }

    // MARK: - Helpers

    private func makeTestSocket() -> (path: String, cleanup: () -> Void) {
        let path = NSTemporaryDirectory() + "yoink-test-\(UUID().uuidString).sock"
        return (path, { unlink(path) })
    }

    private func startTestListener(path: String, handler: @escaping @Sendable ([String]) -> Void) -> DispatchSourceProtocol? {
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { XCTFail("Failed to create socket"); return nil }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
        withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
            pathPtr.withMemoryRebound(to: CChar.self, capacity: maxLen + 1) { buf in
                _ = path.withCString { strncpy(buf, $0, maxLen) }
                buf[maxLen] = 0
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { XCTFail("Failed to bind: \(String(cString: strerror(errno)))"); close(fd); return nil }
        guard listen(fd, 5) == 0 else { XCTFail("Failed to listen"); close(fd); return nil }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global())
        source.setEventHandler {
            let clientFd = accept(fd, nil, nil)
            guard clientFd >= 0 else { return }
            defer { close(clientFd) }

            var buf = [UInt8](repeating: 0, count: 1024)
            let n = read(clientFd, &buf, buf.count)
            guard n > 0 else { return }
            let message = String(decoding: buf.prefix(n), as: UTF8.self)
            let args = message.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            handler(args)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func sendTestArgs(_ args: [String], path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
        withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
            pathPtr.withMemoryRebound(to: CChar.self, capacity: maxLen + 1) { buf in
                _ = path.withCString { strncpy(buf, $0, maxLen) }
                buf[maxLen] = 0
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Foundation.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { return false }

        let bytes = Array(args.joined(separator: "\0").utf8)
        let written = bytes.withUnsafeBufferPointer { buf in
            write(fd, buf.baseAddress, buf.count)
        }
        return written == bytes.count
    }
}
