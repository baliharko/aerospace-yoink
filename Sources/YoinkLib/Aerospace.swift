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

    /// Fetch workspace + windows + focused window in parallel for speed.
    /// Pass a pre-built icon cache to avoid rebuilding it on every activation.
    static func fetchWindows(
        iconCache: [String: NSImage],
        defaultIcon: NSImage
    ) -> (workspace: String, windows: [AeroWindow], focusedId: Int?) {
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

        guard !rawOutput.isEmpty else { return (workspace, [], focusedId) }

        let windows = parseWindowList(rawOutput, excluding: workspace,
                                      iconCache: iconCache, defaultIcon: defaultIcon)
        return (workspace, windows, focusedId)
    }

    /// Parse `list-windows --all --format "%{window-id}|%{workspace}|%{app-name}|%{window-title}"`
    /// output into AeroWindow models. Excludes windows on `currentWorkspace`.
    static func parseWindowList(
        _ raw: String, excluding currentWorkspace: String,
        iconCache: [String: NSImage] = [:], defaultIcon: NSImage = NSImage()
    ) -> [AeroWindow] {
        raw.split(separator: "\n").compactMap { line in
            let p = line.split(separator: "|", maxSplits: 3).map(String.init)
            guard p.count == 4,
                  let id = Int(p[0].trimmingCharacters(in: .whitespaces))
            else { return nil }
            let space = p[1].trimmingCharacters(in: .whitespaces)
            if space == currentWorkspace { return nil }
            let appName = p[2].trimmingCharacters(in: .whitespaces)
            return AeroWindow(
                id: id, workspace: space,
                appName: appName,
                title: p[3].trimmingCharacters(in: .whitespaces),
                icon: iconCache[appName] ?? defaultIcon
            )
        }
    }

    /// Parse `list-windows --all --format "%{window-id}|%{workspace}"` output.
    static func parseWindowLocations(_ raw: String) -> [(windowId: Int, workspace: String)] {
        guard !raw.isEmpty else { return [] }
        return raw.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let id = Int(parts[0].trimmingCharacters(in: .whitespaces))
            else { return nil }
            return (id, parts[1].trimmingCharacters(in: .whitespaces))
        }
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
        return parseWindowLocations(raw)
    }
}
