import Foundation

let socketPath = "/tmp/yoink.sock"

enum YoinkCommand: Equatable {
    case yoink(focus: Bool)
    case unyoink

    var rawValue: String {
        switch self {
        case .yoink(let focus): focus ? "yoink --focus" : "yoink"
        case .unyoink: "unyoink"
        }
    }

    static func parse(_ string: String) -> YoinkCommand? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed {
        case "yoink": return .yoink(focus: false)
        case "yoink --focus": return .yoink(focus: true)
        case "unyoink": return .unyoink
        default: return nil
        }
    }
}

/// Sends a command to the running daemon over the Unix socket.
/// Returns true if the command was sent successfully.
func sendCommand(_ command: YoinkCommand) -> Bool {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
        pathPtr.withMemoryRebound(to: CChar.self, capacity: 104) { buf in
            _ = socketPath.withCString { strncpy(buf, $0, 104) }
        }
    }

    let connectResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            Foundation.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connectResult == 0 else { return false }

    let message = command.rawValue
    _ = message.withCString { write(fd, $0, strlen($0)) }
    return true
}

/// Retained dispatch source for the socket listener — prevents deallocation.
private nonisolated(unsafe) var _socketSource: DispatchSourceProtocol?

/// Listens on a Unix domain socket and dispatches commands to the handler.
/// Runs on a background queue. The handler is called on the main queue.
func startSocketListener(handler: @escaping @Sendable (YoinkCommand) -> Void) {
    // Clean up stale socket
    unlink(socketPath)

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        fputs("yoink: failed to create socket\n", stderr)
        return
    }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
        pathPtr.withMemoryRebound(to: CChar.self, capacity: 104) { buf in
            _ = socketPath.withCString { strncpy(buf, $0, 104) }
        }
    }

    let bindResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard bindResult == 0 else {
        fputs("yoink: failed to bind socket: \(String(cString: strerror(errno)))\n", stderr)
        close(fd)
        return
    }

    guard listen(fd, 5) == 0 else {
        fputs("yoink: failed to listen on socket\n", stderr)
        close(fd)
        return
    }

    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global())
    source.setEventHandler {
        let clientFd = accept(fd, nil, nil)
        guard clientFd >= 0 else { return }
        defer { close(clientFd) }

        var buf = [CChar](repeating: 0, count: 256)
        let n = read(clientFd, &buf, buf.count - 1)
        guard n > 0 else { return }
        let message = String(decoding: buf.prefix(n).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        if let command = YoinkCommand.parse(message) {
            DispatchQueue.main.async { handler(command) }
        }
    }
    source.setCancelHandler { close(fd) }
    _socketSource = source
    source.resume()
}
