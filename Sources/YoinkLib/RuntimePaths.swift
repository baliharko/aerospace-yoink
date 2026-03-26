import Foundation

/// User-scoped runtime directory and file paths for the yoink daemon.
/// Uses $XDG_RUNTIME_DIR if set, otherwise falls back to $TMPDIR/yoink-$UID/.
/// The directory is created with 0700 permissions on first access.
public enum RuntimePaths {
    public static let dir: String = {
        let base: String
        if let xdg = ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"] {
            base = "\(xdg)/yoink"
        } else {
            let tmpdir = NSTemporaryDirectory().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            base = "/\(tmpdir)/yoink-\(getuid())"
        }
        return base
    }()

    public static let pidFile = "\(dir)/yoink.pid"
    public static let socketPath = "\(dir)/yoink.sock"

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
