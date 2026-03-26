import Foundation

public struct YoinkEntry {
    public let windowId: Int
    public let originWorkspace: String
    public var destinationWorkspace: String
}

public class YoinkStack {
    public private(set) var entries: [YoinkEntry] = []
    private var pidFilePath: String { RuntimePaths.pidFile }

    public init() {}

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

    /// Persist PID and stack to the pid file.
    public func save(pid: pid_t) {
        var lines = ["\(pid)"]
        for entry in entries {
            lines.append("\(entry.windowId)|\(entry.originWorkspace)|\(entry.destinationWorkspace)")
        }
        try? lines.joined(separator: "\n").write(
            toFile: pidFilePath, atomically: true, encoding: .utf8
        )
    }

    /// Load stack from pid file. Only restores entries if the stored PID matches.
    public func load(pid: pid_t) {
        guard let content = try? String(contentsOfFile: pidFilePath, encoding: .utf8) else { return }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let firstLine = lines.first,
              let storedPid = pid_t(firstLine.trimmingCharacters(in: .whitespacesAndNewlines)),
              storedPid == pid
        else { return }

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
