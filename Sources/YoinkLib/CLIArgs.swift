import Foundation

public struct CLIArgs: Sendable, Equatable {
    public var isDaemon: Bool = false
    public var isYeet: Bool = false
    public var noFocus: Bool = false

    public init() {}

    public init(arguments: [String]) {
        for arg in arguments {
            switch arg {
            case "--daemon": isDaemon = true
            case "--yeet": isYeet = true
            case "--no-focus": noFocus = true
            default: break
            }
        }
    }
}
