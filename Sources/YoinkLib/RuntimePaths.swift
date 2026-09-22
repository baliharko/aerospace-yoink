import Foundation

/// User-scoped runtime directory and file paths for the yoink daemon.
/// Uses $XDG_RUNTIME_DIR if set, otherwise falls back to $TMPDIR/yoink-$UID/.
/// The directory is created with 0700 permissions on first access.
public enum RuntimePaths {
    /// Settable so tests can point it at a scratch directory — the default is
    /// shared with any daemon the developer has running.
    nonisolated(unsafe) public internal(set) static var dir: String = {
        let base: String
        if let xdg = ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"] {
            base = "\(xdg)/yoink"
        } else {
            let tmpdir = NSTemporaryDirectory().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            base = "/\(tmpdir)/yoink-\(getuid())"
        }
        return base
    }()

    public static var pidFile: String { "\(dir)/yoink.pid" }
    public static var socketPath: String { "\(dir)/yoink.sock" }
    /// Yoink stack. Unlike the PID file and socket, it outlives the daemon.
    public static var stackFile: String { "\(dir)/yoink.stack" }
    /// See `DaemonLock`. Never deleted.
    public static var lockFile: String { "\(dir)/yoink.lock" }

    /// Creates the runtime directory with user-only permissions (0700).
    /// Throws if the directory cannot be created or secured.
    public static func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // Enforce permissions even if directory already existed
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: dir
        )
    }
}
