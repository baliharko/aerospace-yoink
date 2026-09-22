import AppKit

enum Aerospace {
    private static let bin: String = {
        for p in ["/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace"]
            where FileManager.default.fileExists(atPath: p) {
            return p
        }
        return "/opt/homebrew/bin/aerospace"
    }()

    /// Upper bound on one CLI call. Calls normally take ~15ms; this only trips
    /// when the AeroSpace server is wedged, so a hung call can't pin its
    /// thread — and whatever is waiting on it — forever.
    static let timeout: TimeInterval = 2

    /// Runs `aerospace` and returns its trimmed stdout, or nil if it couldn't
    /// be launched, exited non-zero, or timed out. Callers that act on the
    /// absence of output must treat nil (AeroSpace unreachable) differently
    /// from "" (a valid empty result). Blocks the calling thread.
    @discardableResult
    static func run(_ args: [String]) -> String? {
        let proc = Process()
        let pipe = Pipe()
        let cmd = args.first ?? ""
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = args
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            fputs("yoink: failed to run aerospace: \(error.localizedDescription)\n", stderr)
            return nil
        }
        let watchdog = DispatchWorkItem {
            guard proc.isRunning else { return }
            fputs("yoink: aerospace \(cmd) timed out after \(timeout)s\n", stderr)
            proc.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        // Drain the pipe before waiting — waiting first deadlocks once the
        // child fills the pipe buffer (large list-windows output).
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        watchdog.cancel()
        guard proc.terminationReason == .exit, proc.terminationStatus == 0 else {
            let how = proc.terminationReason == .exit ? "exited with status" : "was killed by signal"
            fputs("yoink: aerospace \(cmd) \(how) \(proc.terminationStatus)\n", stderr)
            return nil
        }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Returns true if the aerospace binary exists on disk
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: bin)
    }

    /// Fetch the focused workspace (with its screen), windows, and focused window
    /// in parallel for speed. Pass a pre-built icon cache to avoid rebuilding it
    /// on every activation. The screen comes back as an index into
    /// `NSScreen.screens` for the caller to resolve on the main thread.
    static func fetchWindows(
        iconCache: [pid_t: NSImage],
        defaultIcon: NSImage
    ) -> (workspace: String, windows: [AeroWindow], focusedId: Int?, screenIndex: Int?) {
        guard isInstalled else {
            fputs("yoink: aerospace binary not found at \(bin)\n", stderr)
            return ("", [], nil, nil)
        }
        // nonisolated(unsafe) is safe here: each var is written exactly once
        // on a background thread, and group.wait() provides a happens-before
        // barrier before any reads on the calling thread.
        nonisolated(unsafe) var focusedWorkspace = ""
        nonisolated(unsafe) var rawOutput = ""
        nonisolated(unsafe) var focusedId: Int? = nil
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global().async {
            // The workspace and its screen in one call. The screen's AppKit index,
            // unlike its name, is unique even across identical monitors.
            focusedWorkspace = run(["list-workspaces", "--focused", "--format",
                                    "%{monitor-appkit-nsscreen-screens-id}|%{workspace}"]) ?? ""
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            rawOutput = run(["list-windows", "--all", "--json", "--format", windowListFormat]) ?? ""
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            focusedId = focusedWindowId()
            group.leave()
        }
        group.wait()

        let (workspace, screenIndex) = parseFocusedWorkspace(focusedWorkspace)

        guard !rawOutput.isEmpty else { return (workspace, [], focusedId, screenIndex) }

        let windows = parseWindowList(rawOutput, excluding: workspace,
                                      iconCache: iconCache, defaultIcon: defaultIcon)
        return (workspace, windows, focusedId, screenIndex)
    }

    /// Parse `list-workspaces --focused --format "%{monitor-appkit-nsscreen-screens-id}|%{workspace}"`.
    /// AeroSpace's screen ID is 1-based; the returned index is 0-based. Returns an
    /// empty workspace if the output is malformed (e.g. the query failed).
    static func parseFocusedWorkspace(_ raw: String) -> (workspace: String, screenIndex: Int?) {
        let parts = raw.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return ("", nil) }
        let screenId = Int(parts[0].trimmingCharacters(in: .whitespaces))
        return (parts[1].trimmingCharacters(in: .whitespaces), screenId.map { $0 - 1 })
    }

    /// Fields requested from `list-windows --all --json`. JSON keeps window
    /// titles containing `|` or newlines intact, which a delimited format can't.
    static let windowListFormat = "%{window-id} %{app-pid} %{workspace} %{app-name} %{window-title}"

    private struct WindowRecord: Decodable {
        let windowId: Int
        let appPid: pid_t
        let workspace: String
        let appName: String
        let windowTitle: String

        enum CodingKeys: String, CodingKey {
            case workspace
            case windowId = "window-id", appPid = "app-pid"
            case appName = "app-name", windowTitle = "window-title"
        }
    }

    /// Parse `list-windows --all --json --format windowListFormat` output into
    /// AeroWindow models, excluding windows on `currentWorkspace`. Icons are
    /// matched by process ID, so apps that share a name can't swap icons.
    static func parseWindowList(
        _ json: String, excluding currentWorkspace: String,
        iconCache: [pid_t: NSImage] = [:], defaultIcon: NSImage = NSImage()
    ) -> [AeroWindow] {
        guard !json.isEmpty else { return [] }
        let records: [WindowRecord]
        do {
            records = try JSONDecoder().decode([WindowRecord].self, from: Data(json.utf8))
        } catch {
            fputs("yoink: couldn't parse aerospace window list: \(error)\n", stderr)
            return []
        }
        return records.filter { $0.workspace != currentWorkspace }.map { record in
            AeroWindow(
                id: record.windowId, workspace: record.workspace,
                appName: record.appName,
                title: record.windowTitle,
                icon: iconCache[record.appPid] ?? defaultIcon
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
        run(["list-windows", "--focused", "--format", "%{window-id}"]).flatMap { Int($0) }
    }

    /// Lightweight query returning window IDs and their current workspaces,
    /// or nil if AeroSpace couldn't be queried.
    static func listAllWindowLocations() -> [(windowId: Int, workspace: String)]? {
        run(["list-windows", "--all", "--format", "%{window-id}|%{workspace}"])
            .map(parseWindowLocations)
    }
}
