import Foundation

public struct YoinkEntry: Sendable {
    public let windowId: Int
    public let originWorkspace: String
    public var destinationWorkspace: String
}

public class YoinkStack {
    public private(set) var entries: [YoinkEntry] = []
    private let session: String
    private var path: String { RuntimePaths.stackFile }

    /// Identifies the login session the stack's window IDs belong to. They come
    /// from WindowServer and get reused after a reboot or re-login, where a
    /// stale entry could point at an unrelated window.
    public static let currentSession: String = {
        var boottime = timeval()
        var size = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &boottime, &size, nil, 0)
        var audit = auditinfo_addr()
        getaudit_addr(&audit, Int32(MemoryLayout<auditinfo_addr>.size))
        return "\(boottime.tv_sec)-\(audit.ai_asid)"
    }()

    public init(session: String = YoinkStack.currentSession) {
        self.session = session
    }

    public var isEmpty: Bool { entries.isEmpty }

    /// Push a yoinked window. If it already exists, preserve its origin and move to top.
    public func push(windowId: Int, originWorkspace: String, destinationWorkspace: String) {
        if let idx = entries.firstIndex(where: { $0.windowId == windowId }) {
            var entry = entries.remove(at: idx)
            entry.destinationWorkspace = destinationWorkspace
            entries.insert(entry, at: 0)
        } else {
            entries.insert(YoinkEntry(
                windowId: windowId,
                originWorkspace: originWorkspace,
                destinationWorkspace: destinationWorkspace
            ), at: 0)
        }
    }

    /// Pop the most recently yoinked window.
    public func pop() -> YoinkEntry? {
        guard !entries.isEmpty else { return nil }
        return entries.removeFirst()
    }

    /// Remove a specific window (e.g. when manual move detected).
    public func remove(windowId: Int) {
        entries.removeAll { $0.windowId == windowId }
    }

    /// Persist the stack, tagged with its session. It lives in its own file
    /// rather than the PID file so it survives clean daemon restarts.
    public func save() {
        guard !entries.isEmpty else {
            unlink(path)
            return
        }
        var lines = [session]
        for entry in entries {
            lines.append("\(entry.windowId)|\(entry.originWorkspace)|\(entry.destinationWorkspace)")
        }
        try? lines.joined(separator: "\n").write(
            toFile: path, atomically: true, encoding: .utf8
        )
    }

    /// Load the stack a previous daemon left behind in this same session.
    /// Entries whose windows have since closed or moved are pruned by the
    /// location poll once the daemon is up.
    public func load() {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first == session else { return }

        entries = lines.dropFirst().compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 2).map(String.init)
            guard parts.count == 3, let windowId = Int(parts[0]) else { return nil }
            return YoinkEntry(
                windowId: windowId,
                originWorkspace: parts[1],
                destinationWorkspace: parts[2]
            )
        }
    }
}
