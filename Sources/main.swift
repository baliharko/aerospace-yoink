import AppKit

let pidFile = "/tmp/yoink.pid"
let isUnyoink = CommandLine.arguments.contains("--unyoink")
let wantsFocus = CommandLine.arguments.contains("--focus")

// If an existing daemon is running, send command via socket and exit
if let pidStr = try? String(contentsOfFile: pidFile, encoding: .utf8)
    .components(separatedBy: "\n").first?
    .trimmingCharacters(in: .whitespacesAndNewlines),
    let pid = pid_t(pidStr),
    pid != getpid(),
    kill(pid, 0) == 0
{
    // Verify the PID is actually a yoink process (guards against stale PID reuse)
    let check = Process()
    let pipe = Pipe()
    check.executableURL = URL(fileURLWithPath: "/bin/ps")
    check.arguments = ["-p", "\(pid)", "-o", "comm="]
    check.standardOutput = pipe
    try? check.run()
    check.waitUntilExit()
    let comm = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if comm.hasSuffix("yoink") {
        let command: YoinkCommand = isUnyoink ? .unyoink : .yoink(focus: wantsFocus)
        if sendCommand(command) {
            exit(0)
        }
        fputs("yoink: failed to connect to daemon\n", stderr)
        exit(1)
    }
    // Stale PID file — fall through to become the new daemon
}

// --unyoink with no running daemon is a no-op
if isUnyoink {
    fputs("yoink: no daemon running\n", stderr)
    exit(1)
}

// Become the daemon — write PID file (clears any old stack data)
let stack = YoinkStack()
let currentPid = getpid()
try? "\(currentPid)".write(toFile: pidFile, atomically: true, encoding: .utf8)

// Clean up PID file and socket on exit
atexit {
    unlink(pidFile)
    unlink(socketPath)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let controller = YoinkController(stack: stack, pid: currentPid)

// Listen for commands on Unix domain socket
startSocketListener { command in
    MainActor.assumeIsolated {
        switch command {
        case .yoink(let focus):
            controller.activate(focus: focus)
        case .unyoink:
            controller.unyoink()
        }
    }
}

// Show immediately on first launch unless started as background daemon
if !CommandLine.arguments.contains("--daemon") && !isUnyoink {
    DispatchQueue.main.async { controller.activate(focus: wantsFocus) }
}

app.run()
