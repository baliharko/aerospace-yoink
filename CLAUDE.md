# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Yoink is a native macOS daemon that provides a keyboard-driven window picker for AeroSpace (tiling window manager). It lets you pull ("yoink") windows from other workspaces into your current one. Built with Swift/AppKit, no external dependencies.

**Requirements:** Swift 6.2+, macOS 26+ (Tahoe) — the UI uses `NSGlassEffectView` which requires macOS 26.

## Build & Run

```bash
swift build                    # Debug build
swift build -c release         # Release build

# Run as daemon (stays resident, listens on a Unix domain socket)
swift build -c release && .build/release/yoink --daemon

# Trigger picker (forwards args over socket to running daemon)
.build/release/yoink
```

Run tests with `swift test`. Lint with `swiftlint lint` (config in `.swiftlint.yml`). No formatter is configured.

## Architecture

**Daemon IPC pattern:** Runtime files live in a user-scoped directory (`$XDG_RUNTIME_DIR/yoink/` or `$TMPDIR/yoink-$UID/`). Every launch first tries to forward its CLI args over the daemon's Unix domain socket there. If nothing answers, it takes an exclusive `flock` on `yoink.lock` (`DaemonLock`) and becomes the daemon. A launch that loses the lock race forwards to the winner once its socket is up. The yoink stack is persisted to `yoink.stack`, tagged with the login session. Tests point `RuntimePaths.dir` at a scratch directory (`RuntimeDirTestCase`) so they never touch a running daemon.

**Data flow:** `main.swift` → `YoinkController` (manages panel lifecycle, keyboard input, search filtering) → `Aerospace` (shells out to `aerospace` CLI to list workspaces/windows, move windows) → `AeroWindow` (data model).

**UI layer:** `Views.swift` defines `YoinkPanel` (NSPanel subclass with glass effect), `WindowCell` (renders app icon, name, title, workspace badge), and `WindowRowView` (custom selection highlight). `Layout.swift` centralizes all design constants as a nested enum.

**Performance:** Window data is fetched via parallel `aerospace` CLI calls using DispatchGroup. App icons are cached from NSWorkspace.
