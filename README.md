# Yoink

A fast, native macOS window picker for [AeroSpace](https://github.com/nikitabobko/AeroSpace). Pull any window from another workspace into your current one — without leaving it.

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-blue)
![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange)

## What it does

Press a keybinding and a floating Liquid Glass panel appears, listing every window from your other AeroSpace workspaces. Select one and it gets moved or "**yoinked**" into your focused workspace.

- Runs as a background daemon — instant response on hotkey press
- Type-to-filter search that dynamically resizes the panel
- Keyboard-driven: arrow keys to navigate, Enter to yoink, Escape to dismiss
- Shows app icons, names, window titles, and workspace badges
- Adapts to screen size and works across multiple monitors

## Requirements

- **macOS 26** (Tahoe) or later — required for `NSGlassEffectView`
- **Swift 6.2** toolchain
- **AeroSpace** window manager (v0.20+)

## Installation

### Quick install

```bash
git clone https://github.com/YOUR_USERNAME/aerospace-yoink.git
cd aerospace-yoink
bash install.sh
```

This builds the release binary, installs it to `/usr/local/bin/yoink`, and sets up a LaunchAgent so the daemon starts automatically on login and respawns if it crashes.

### Build from source (manual)

```bash
swift build -c release
```

The binary will be at `.build/release/yoink`. Copy it somewhere in your `$PATH`:

```bash
sudo cp .build/release/yoink /usr/local/bin/yoink
sudo codesign --force --sign - /usr/local/bin/yoink
```

Note: re-signing is required after copying, otherwise macOS will kill the binary.

## Configuration

### Yoink config

Create `~/.yoink.toml` (or `$XDG_CONFIG_HOME/yoink/yoink.toml`) to customize behavior:

```toml
fade-in = 0.1          # Panel fade-in duration in seconds (default: 0.1)
fade-out = 0.08        # Panel fade-out duration in seconds (default: 0.08)
focus-after-yoink = true  # Focus the yoinked window (default: true)
```

All fields are optional — defaults are used for any missing keys.

### AeroSpace integration

Add these lines to your AeroSpace config (`~/.config/aerospace/aerospace.toml`):

#### Start the daemon on AeroSpace startup

```toml
after-startup-command = ['exec-and-forget /path/to/yoink --daemon']
```

#### Bind a hotkey to trigger the picker

```toml
[mode.main.binding]
    alt-shift-ctrl-cmd-y = 'exec-and-forget /path/to/yoink'
```

Replace `/path/to/yoink` with the actual path to the binary (e.g., `/usr/local/bin/yoink` or the full `.build/release/yoink` path).

## Usage

| Key | Action |
|---|---|
| Arrow keys | Navigate the list |
| Enter | Yoink the selected window |
| Escape | Clear search, or dismiss if search is empty |
| Any letter | Opens the filter field and starts filtering |

### Flags

| Flag | Effect |
|---|---|
| `--daemon` | Start as a background daemon without showing the picker |
| `--no-focus` | Move the window without focusing it (default: focus the yoinked window) |
| `--yeet` | Send the most recently yoinked window back to its origin workspace |

### How it works

1. **First invocation with `--daemon`**: Starts a background process that stays resident and listens on a Unix domain socket. No UI is shown.
2. **Subsequent invocations** (without `--daemon`): Detects the running daemon via a PID file, forwards CLI args over the socket, and exits immediately. The daemon receives the args and acts on them (e.g. shows the picker).
3. **Without a daemon**: If no daemon is running, the binary becomes the daemon and shows the panel immediately.

Runtime files (PID file, socket) are stored in a user-scoped directory (`$XDG_RUNTIME_DIR/yoink/` or `$TMPDIR/yoink-$UID/`) with `0700` permissions.

This means the hotkey response is near-instant — there's no process startup overhead on each press.

## Yeeting

Yoink keeps a stack of where each yoinked window came from. Running `yoink --yeet` pops the most recent entry and sends that window back to its original workspace — handy when you pulled something over by mistake or are done with it.

You can bind it to a hotkey alongside the regular yoink trigger:

```toml
[mode.main.binding]
    alt-shift-ctrl-cmd-u = 'exec-and-forget /path/to/yoink --yeet'
```

The stack is automatically cleaned up: if you manually move a yoinked window to a different workspace, it gets removed from the stack so yeet won't try to move it again.

## How AeroSpace discovers the binary

Yoink looks for the `aerospace` CLI in these locations (in order):

1. `/opt/homebrew/bin/aerospace` (Homebrew on Apple Silicon)
2. `/usr/local/bin/aerospace` (Homebrew on Intel / manual install)

If your `aerospace` binary is elsewhere, you'll need to symlink it to one of these paths.

## Project structure

```
Sources/
  YoinkApp/
    main.swift            # Daemon entry point, PID file, socket IPC
  YoinkLib/
    Aerospace.swift       # AeroSpace CLI wrapper, window fetching
    AeroWindow.swift      # Window data model
    CLIArgs.swift         # Command-line argument parsing
    Config.swift          # TOML config parser
    IPC.swift             # Unix domain socket client/server
    Layout.swift          # UI layout constants
    RuntimePaths.swift    # User-scoped runtime directory paths
    Views.swift           # Panel, cell, and row view classes
    YoinkController.swift # UI controller, search, keyboard handling
    YoinkStack.swift      # Tracks yoinked window origins for yeet
Tests/
  AeroWindowTests.swift     # Window matching/search tests
  CLIArgsTests.swift        # CLI argument parsing tests
  ConfigTests.swift         # Config/TOML parser tests
  DaemonStartupTests.swift  # Daemon startup sequence tests
  IPCTests.swift            # IPC round-trip tests
  YoinkStackTests.swift     # Yoink/yeet stack tests
install.sh                  # Build, install, and start LaunchAgent
com.yoink.daemon.plist      # LaunchAgent for auto-start on login
Package.swift
```

## License

MIT

