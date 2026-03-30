import Foundation

public struct Config: Sendable {
    public var fadeIn: CGFloat = 0.1
    public var fadeOut: CGFloat = 0.08
    public var focusAfterYoink: Bool = true

    /// Searches for config in order:
    /// 1. `~/.yoink.toml`
    /// 2. `$XDG_CONFIG_HOME/yoink/yoink.toml` (defaults to `~/.config/yoink/yoink.toml`)
    public static func load() -> Config {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        let candidates: [String] = [
            "\(home)/.yoink.toml",
            {
                let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
                    ?? "\(home)/.config"
                return "\(xdg)/yoink/yoink.toml"
            }(),
        ]

        for path in candidates {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            do {
                let content = try String(contentsOfFile: path, encoding: .utf8)
                var config = Config()
                config.parse(content, path: path)
                return config
            } catch {
                fputs("yoink: failed to read \(path): \(error.localizedDescription)\n", stderr)
            }
        }

        // No config found — write defaults to XDG config path
        writeDefault()
        return Config()
    }

    /// Default config content as TOML with all values shown.
    public static let defaultTOML = """
        # Yoink configuration
        # Place this file at ~/.yoink.toml or ~/.config/yoink/yoink.toml

        # Duration (seconds) for the panel fade-in animation
        fade-in = 0.1

        # Duration (seconds) for the panel fade-out animation
        fade-out = 0.08

        # Whether to focus the yoinked window after moving it
        focus-after-yoink = true

        """

    /// Writes the default config file. Returns the path written, or nil on failure.
    @discardableResult
    public static func writeDefault() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            ?? "\(home)/.config"
        let dir = "\(xdg)/yoink"
        let path = "\(dir)/yoink.toml"

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

    /// Parse a TOML string into a config. Used by `load()` and tests.
    public mutating func parse(_ content: String, path: String = "<string>") {
        for (lineNumber, line) in content.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            guard let eqIdx = trimmed.firstIndex(of: "=") else {
                fputs("yoink: \(path):\(lineNumber + 1): expected 'key = value'\n", stderr)
                continue
            }

            let key = trimmed[trimmed.startIndex..<eqIdx].trimmingCharacters(in: .whitespaces)
            let raw = trimmed[trimmed.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces)

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
