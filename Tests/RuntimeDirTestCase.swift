import XCTest
@testable import YoinkLib

/// Per-process scratch runtime directory. Kept short: the socket path inside
/// it has to fit in sockaddr_un.sun_path (104 bytes).
let scratchRuntimeDir = NSTemporaryDirectory() + "yoink-test-\(getpid())"

/// Base class for tests that touch the daemon's runtime files. The default
/// runtime directory is shared with any daemon running on this machine, so
/// without this a test run would unlink and rebind its socket and overwrite
/// its yoink stack.
class RuntimeDirTestCase: XCTestCase {
    override func setUp() {
        super.setUp()
        RuntimePaths.dir = scratchRuntimeDir
    }

    override class func tearDown() {
        try? FileManager.default.removeItem(atPath: scratchRuntimeDir)
        super.tearDown()
    }
}
