import Foundation

public var socketPath: String { RuntimePaths.socketPath }

// MARK: - Socket address helpers

private func makeUnixAddress(path: String) -> sockaddr_un? {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let maxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1 // reserve null terminator
    guard path.utf8.count <= maxLen else {
        fputs("yoink: socket path too long (\(path.utf8.count) > \(maxLen) bytes)\n", stderr)
        return nil
    }
    withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
        pathPtr.withMemoryRebound(to: CChar.self, capacity: maxLen + 1) { buf in
            _ = path.withCString { strncpy(buf, $0, maxLen) }
            buf[maxLen] = 0
        }
    }
    return addr
}

private func withSockAddr<T>(_ addr: inout sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
    withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            body(sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
}

// MARK: - Client

/// Sends CLI arguments to the running daemon over the Unix socket.
/// Arguments are joined with null bytes as separators.
/// Returns true if the full message was sent successfully.
public func sendArgs(_ args: [String]) -> Bool {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }

    guard var addr = makeUnixAddress(path: socketPath) else { return false }
    let connectResult = withSockAddr(&addr) { Foundation.connect(fd, $0, $1) }
    guard connectResult == 0 else { return false }

    let bytes = Array(args.joined(separator: "\0").utf8)
    var offset = 0
    while offset < bytes.count {
        let n = bytes.withUnsafeBufferPointer { buf in
            write(fd, buf.baseAddress! + offset, bytes.count - offset)
        }
        guard n > 0 else { return false }
        offset += n
    }
    return true
}

// MARK: - Server

/// Retained dispatch source for the socket listener — prevents deallocation.
private nonisolated(unsafe) var _socketSource: DispatchSourceProtocol?

/// Listens on a Unix domain socket for incoming argument lists.
/// Runs on a background queue. The handler is called on the main queue.
/// Returns true if the socket was successfully bound and is listening.
@discardableResult
public func startSocketListener(handler: @escaping @Sendable ([String]) -> Void) -> Bool {
    // Clean up stale socket
    unlink(socketPath)

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        fputs("yoink: failed to create socket\n", stderr)
        return false
    }

    guard var addr = makeUnixAddress(path: socketPath) else {
        close(fd)
        return false
    }
    let bindResult = withSockAddr(&addr) { bind(fd, $0, $1) }
    guard bindResult == 0 else {
        fputs("yoink: failed to bind socket: \(String(cString: strerror(errno)))\n", stderr)
        close(fd)
        return false
    }

    guard listen(fd, 5) == 0 else {
        fputs("yoink: failed to listen on socket\n", stderr)
        close(fd)
        return false
    }

    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global())
    source.setEventHandler {
        let clientFd = accept(fd, nil, nil)
        guard clientFd >= 0 else { return }
        defer { close(clientFd) }

        // Read until EOF — don't assume message fits in a fixed buffer
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 1024)
        while true {
            let n = read(clientFd, &buf, buf.count)
            if n <= 0 { break }
            data.append(contentsOf: buf.prefix(n))
            // Guard against oversized messages (16 KB is far beyond any realistic arg list)
            if data.count > 16384 { break }
        }
        let args = data.isEmpty ? [] : String(decoding: data, as: UTF8.self)
            .split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        DispatchQueue.main.async { handler(args) }
    }
    source.setCancelHandler { close(fd) }
    _socketSource = source
    source.resume()
    return true
}
