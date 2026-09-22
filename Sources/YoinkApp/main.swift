import AppKit
import YoinkLib

let args = CLIArgs(arguments: CommandLine.arguments)
let forwardedArgs = Array(CommandLine.arguments.dropFirst())

// If an existing daemon is running, forward args via socket and exit.
// A successful socket connection is proof enough — no need to verify the PID
// via /bin/ps (which costs ~67ms due to Process() overhead).
if sendArgs(forwardedArgs) {
    exit(0)
}

do {
    try RuntimePaths.ensureDirectory()
} catch {
    fputs("yoink: failed to create runtime directory: \(error.localizedDescription)\n", stderr)
    exit(1)
}

// Only the lock holder may become the daemon. If another launch holds it,
// hand our args to that one instead of racing it for the socket.
do {
    switch try DaemonLock.acquireOrForward(forwardedArgs) {
    case .daemon:
        break // the lock fd is deliberately never closed: held until exit
    case .forwarded:
        exit(0)
    case .timedOut:
        fputs("yoink: another launch holds the daemon lock but isn't accepting commands\n", stderr)
        exit(1)
    }
} catch {
    fputs("yoink: failed to take daemon lock: \(error.localizedDescription)\n", stderr)
    exit(1)
}

// --yeet with no running daemon is a no-op
if args.isYeet {
    fputs("yoink: no daemon running\n", stderr)
    exit(1)
}

// Become the daemon. Holding the lock means no other daemon is alive, so
// restoring the previous daemon's stack and claiming the PID file are safe.
let config = Config.load()
let stack = YoinkStack()
stack.load()
let currentPid = getpid()
let pidFile = RuntimePaths.pidFile
do {
    try "\(currentPid)".write(toFile: pidFile, atomically: true, encoding: .utf8)
} catch {
    fputs("yoink: failed to write PID file: \(error.localizedDescription)\n", stderr)
    exit(1)
}

// Clean up PID file and socket on exit. The lock is still held while atexit
// handlers run, so both are guaranteed to be ours. The lock and stack files
// stay.
atexit {
    unlink(RuntimePaths.pidFile)
    unlink(RuntimePaths.socketPath)
}

// atexit doesn't run on signals — exit cleanly on SIGTERM/SIGINT (launchd
// stops the daemon with SIGTERM) so the cleanup above still happens.
let signalSources: [DispatchSourceSignal] = [SIGTERM, SIGINT].map { sig in
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler { exit(0) }
    source.resume()
    return source
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let controller = YoinkController(config: config, stack: stack)

// Listen for commands on Unix domain socket
guard startSocketListener(handler: { rawArgs in
    MainActor.assumeIsolated {
        let incoming = CLIArgs(arguments: rawArgs)
        // A second `yoink --daemon` launch forwards its args here — the
        // daemon is already running, so ignore it rather than popping the picker.
        guard !incoming.isDaemon else { return }
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
