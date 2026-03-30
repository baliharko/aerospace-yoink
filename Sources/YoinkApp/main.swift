import AppKit
import YoinkLib

let args = CLIArgs(arguments: CommandLine.arguments)

// If an existing daemon is running, forward args via socket and exit.
// A successful socket connection is proof enough — no need to verify the PID
// via /bin/ps (which costs ~67ms due to Process() overhead).
if sendArgs(Array(CommandLine.arguments.dropFirst())) {
    exit(0)
}

// --yeet with no running daemon is a no-op
if args.isYeet {
    fputs("yoink: no daemon running\n", stderr)
    exit(1)
}

// Become the daemon — create runtime dir and write PID file
let config = Config.load()
do {
    try RuntimePaths.ensureDirectory()
} catch {
    fputs("yoink: failed to create runtime directory: \(error.localizedDescription)\n", stderr)
    exit(1)
}
let stack = YoinkStack()
let currentPid = getpid()
let pidFile = RuntimePaths.pidFile
do {
    try "\(currentPid)".write(toFile: pidFile, atomically: true, encoding: .utf8)
} catch {
    fputs("yoink: failed to write PID file: \(error.localizedDescription)\n", stderr)
    exit(1)
}

// Clean up PID file, socket, and runtime directory on exit
atexit {
    unlink(RuntimePaths.pidFile)
    unlink(RuntimePaths.socketPath)
    rmdir(RuntimePaths.dir) // succeeds only if empty
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let controller = YoinkController(config: config, stack: stack, pid: currentPid)

// Listen for commands on Unix domain socket
guard startSocketListener(handler: { rawArgs in
    MainActor.assumeIsolated {
        let incoming = CLIArgs(arguments: rawArgs)
        if incoming.isYeet {
            controller.yeet()
        } else {
            let focus = incoming.noFocus ? false : config.focusAfterYoink
            controller.activate(focus: focus)
        }
    }
}) else {
    fputs("yoink: failed to start socket listener — daemon cannot receive commands\n", stderr)
    exit(1)
}

// Show immediately on first launch unless started as background daemon
if !args.isDaemon && !args.isYeet {
    let focus = args.noFocus ? false : config.focusAfterYoink
    DispatchQueue.main.async { controller.activate(focus: focus) }
}

app.run()
