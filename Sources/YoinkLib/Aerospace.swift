import AppKit

enum Aerospace {
    private static let bin: String = {
        for p in ["/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace"]
            where FileManager.default.fileExists(atPath: p) {
            return p
        }
        return "/opt/homebrew/bin/aerospace"
    }()

    @discardableResult
    static func run(_ args: [String]) -> String {
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = args
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            fputs("yoink: failed to run aerospace: \(error.localizedDescription)\n", stderr)
            return ""
        }
        proc.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Returns true if the aerospace binary exists on disk
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: bin)
    }

    /// Fetch workspace + windows + focused window in parallel for speed
    static func fetchWindows() -> (workspace: String, windows: [AeroWindow], focusedId: Int?) {
        guard isInstalled else {
            fputs("yoink: aerospace binary not found at \(bin)\n", stderr)
            return ("", [], nil)
        }
        // nonisolated(unsafe) is safe here: each var is written exactly once
        // on a background thread, and group.wait() provides a happens-before
        // barrier before any reads on the calling thread.
        nonisolated(unsafe) var workspace = ""
        nonisolated(unsafe) var rawOutput = ""
        nonisolated(unsafe) var focusedId: Int? = nil
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global().async {
            workspace = run(["list-workspaces", "--focused"])
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            rawOutput = run(["list-windows", "--all", "--format",
                       "%{window-id}|%{workspace}|%{app-name}|%{window-title}"])
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            focusedId = focusedWindowId()
            group.leave()
        }
        group.wait()

        let iconCache = Dictionary(
            NSWorkspace.shared.runningApplications.compactMap { app -> (String, NSImage)? in
                guard let name = app.localizedName, let icon = app.icon else { return nil }
                icon.size = NSSize(width: Layout.Icon.size, height: Layout.Icon.size)
                return (name, icon)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let defaultIcon = NSWorkspace.shared.icon(for: .applicationBundle)
        defaultIcon.size = NSSize(width: Layout.Icon.size, height: Layout.Icon.size)

        guard !rawOutput.isEmpty else { return (workspace, [], focusedId) }

        let windows: [AeroWindow] = rawOutput.split(separator: "\n").compactMap { line in
            let p = line.split(separator: "|", maxSplits: 3).map(String.init)
            guard p.count == 4,
                  let id = Int(p[0].trimmingCharacters(in: .whitespaces))
            else { return nil }
            let space = p[1].trimmingCharacters(in: .whitespaces)
            if space == workspace { return nil }
            let appName = p[2].trimmingCharacters(in: .whitespaces)
            return AeroWindow(
                id: id, workspace: space,
                appName: appName,
                title: p[3].trimmingCharacters(in: .whitespaces),
                icon: iconCache[appName] ?? defaultIcon
            )
        }
        return (workspace, windows, focusedId)
    }

    static func yoink(_ windowId: Int, to workspace: String, focus: Bool = true) {
        run(["move-node-to-workspace", "--window-id", "\(windowId)", workspace])
        if focus {
            run(["focus", "--window-id", "\(windowId)"])
        }
    }

    /// Returns the currently focused window ID, or nil if none.
    static func focusedWindowId() -> Int? {
        let raw = run(["list-windows", "--focused", "--format", "%{window-id}"])
        return Int(raw.trimmingCharacters(in: .whitespaces))
    }

    /// Lightweight query returning window IDs and their current workspaces.
    static func listAllWindowLocations() -> [(windowId: Int, workspace: String)] {
        let raw = run(["list-windows", "--all", "--format", "%{window-id}|%{workspace}"])
        guard !raw.isEmpty else { return [] }
        return raw.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let id = Int(parts[0].trimmingCharacters(in: .whitespaces))
            else { return nil }
            return (id, parts[1].trimmingCharacters(in: .whitespaces))
        }
    }
}
