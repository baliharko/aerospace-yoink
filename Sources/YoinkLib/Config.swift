import Foundation

public struct Config: Sendable {
    public var fadeIn: CGFloat = 0
    public var fadeOut: CGFloat = 0.08
    public var focusAfterYoink: Bool = true

    /// Searches for config in order:
    /// 1. `~/.yoink.toml`
    /// 2. `$XDG_CONFIG_HOME/yoink/yoink.toml` (defaults to `~/.config/yoink/yoink.toml`)
    public static func load() -> Config {
        load(home: FileManager.default.homeDirectoryForCurrentUser.path,
             xdgConfigHome: ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"])
    }

    /// `load()` with the directories passed in, so tests can use a scratch home.
    static func load(home: String, xdgConfigHome: String?) -> Config {
        let xdgPath = "\(xdgConfigHome ?? "\(home)/.config")/yoink/yoink.toml"
        var foundConfig = false

        for path in ["\(home)/.yoink.toml", xdgPath] {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            foundConfig = true
            do {
                let content = try String(contentsOfFile: path, encoding: .utf8)
                var config = Config()
                config.parse(content, path: path)
                return config
            } catch {
                fputs("yoink: failed to read \(path): \(error.localizedDescription)\n", stderr)
            }
        }

        // Write defaults only when there's no config at all — never over one
        // that exists but couldn't be read (bad encoding, permissions).
        if !foundConfig {
            writeDefault(to: xdgPath)
        }
        return Config()
    }

    /// Default config content as TOML with all values shown.
    public static let defaultTOML = """
        # Yoink configuration
        # Place this file at ~/.yoink.toml or ~/.config/yoink/yoink.toml

        # Duration (seconds) for the panel fade-in animation
        fade-in = 0

        # Duration (seconds) for the panel fade-out animation
        fade-out = 0.08

        # Whether to focus the yoinked window after moving it
        focus-after-yoink = true

        """

    /// Writes the default config file to `path`. Returns the path written, or nil on failure.
    @discardableResult
    public static func writeDefault(to path: String) -> String? {
        let dir = (path as NSString).deletingLastPathComponent

        do {
            try FileManager.default.createDirectory(
                atPath: dir, withIntermediateDirectories: true)
            try defaultTOML.write(toFile: path, atomically: true, encoding: .utf8)
            return path
        } catch {
            fputs("yoink: failed to write config: \(error.localizedDescription)\n", stderr)
            return nil
        }
    }

    /// Split a `key = value` line into trimmed key and value,
    /// stripping any inline `#` comment. Returns nil if there is no `=`.
    private static func keyValue(_ trimmed: String) -> (key: String, value: String)? {
        guard let eqIdx = trimmed.firstIndex(of: "=") else { return nil }
        let key = trimmed[trimmed.startIndex..<eqIdx].trimmingCharacters(in: .whitespaces)
        var value = trimmed[trimmed.index(after: eqIdx)...]
        if let hashIdx = value.firstIndex(of: "#") {
            value = value[value.startIndex..<hashIdx]
        }
        return (key, value.trimmingCharacters(in: .whitespaces))
    }

    /// Parse a TOML string into a config. Used by `load()` and tests.
    public mutating func parse(_ content: String, path: String = "<string>") {
        for (lineNumber, line) in content.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            guard let (key, raw) = Self.keyValue(trimmed) else {
                fputs("yoink: \(path):\(lineNumber + 1): expected 'key = value'\n", stderr)
                continue
            }

            switch key {
            case "fade-in":
                guard let v = Double(raw), v >= 0 else {
                    fputs("yoink: \(path):\(lineNumber + 1): fade-in must be a non-negative number\n", stderr)
                    continue
                }
                fadeIn = CGFloat(v)
            case "fade-out":
                guard let v = Double(raw), v >= 0 else {
                    fputs("yoink: \(path):\(lineNumber + 1): fade-out must be a non-negative number\n", stderr)
                    continue
                }
                fadeOut = CGFloat(v)
            case "focus-after-yoink":
                guard raw == "true" || raw == "false" else {
                    fputs("yoink: \(path):\(lineNumber + 1): focus-after-yoink must be true or false\n", stderr)
                    continue
                }
                focusAfterYoink = raw == "true"
            default:
                fputs("yoink: \(path):\(lineNumber + 1): unknown key '\(key)'\n", stderr)
            }
        }
    }
}
