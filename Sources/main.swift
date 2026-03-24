import AppKit

let pidFile = "/tmp/yoink.pid"

// If an existing daemon is running, signal it and exit
if let pidStr = try? String(contentsOfFile: pidFile, encoding: .utf8)
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
        kill(pid, SIGUSR1)
        exit(0)
    }
    // Stale PID file — fall through to become the new daemon
}

// Become the daemon — write PID file
try? "\(getpid())".write(toFile: pidFile, atomically: true, encoding: .utf8)

// Clean up PID file on exit
atexit { unlink(pidFile) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let controller = YoinkController()

// Listen for SIGUSR1 to show panel on subsequent hotkey presses
signal(SIGUSR1, SIG_IGN)
let signalSource = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
signalSource.setEventHandler { controller.activate() }
signalSource.resume()

// Show immediately on first launch unless started as background daemon
if !CommandLine.arguments.contains("--daemon") {
    DispatchQueue.main.async { controller.activate() }
}

app.run()
