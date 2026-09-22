import Foundation

/// Exclusive lock the daemon holds for its whole lifetime. Two launches can
/// both fail to reach a daemon's socket (e.g. the LaunchAgent and AeroSpace's
/// after-startup-command at login); without the lock both would become the
/// daemon, and the second would unlink the first's socket.
public enum DaemonLock {
    /// Takes the lock and returns its fd, which must stay open for as long as
    /// the lock should be held. Returns nil if another process holds it.
    ///
    /// The lock file is never deleted: unlinking it would let a later launch
    /// lock a fresh inode while this one is still held.
    public static func acquire() throws -> Int32? {
        let fd = open(RuntimePaths.lockFile, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let err = errno
            close(fd)
            if err == EWOULDBLOCK { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO)
        }
        return fd
    }

    public enum LaunchRole: Equatable {
        /// Args reached a running daemon.
        case forwarded
        /// We hold the lock (keep the fd open) and should become the daemon.
        case daemon(lockFd: Int32)
        /// Someone held the lock the whole time but never accepted commands.
        case timedOut
    }

    /// Called once the fast-path `sendArgs` has failed: takes the lock, or
    /// else forwards `args` to whoever holds it. Retries because the holder
    /// may still be starting up (socket not bound yet) — or may be a
    /// short-lived launch such as `--yeet` that exits without becoming the
    /// daemon, in which case the lock frees up.
    public static func acquireOrForward(_ args: [String], timeout: TimeInterval = 3) throws -> LaunchRole {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let fd = try acquire() { return .daemon(lockFd: fd) }
            if sendArgs(args) { return .forwarded }
            guard Date() < deadline else { return .timedOut }
            usleep(50_000)
        }
    }
}
