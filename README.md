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

### Build from source

```bash
git clone https://github.com/YOUR_USERNAME/aerospace-yoink.git
cd aerospace-yoink
swift build -c release
```

The binary will be at `.build/release/yoink`.

Optionally, copy it somewhere in your `$PATH`:

```bash
cp .build/release/yoink /usr/local/bin/yoink
```

## Configuration

Add these lines to your AeroSpace config (`~/.config/aerospace/aerospace.toml`):

### Start the daemon on AeroSpace startup

```toml
after-startup-command = ['exec-and-forget /path/to/yoink --daemon']
```

### Bind a hotkey to trigger the picker

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
| `--focus` | Focus the yoinked window after moving it (default: keep focus on the original window) |
| `--unyoink` | Send the most recently yoinked window back to its origin workspace |

### How it works

1. **First invocation with `--daemon`**: Starts a background process that stays resident and listens on a Unix domain socket at `/tmp/yoink.sock`. No UI is shown.
2. **Subsequent invocations** (without `--daemon`): Detects the running daemon via a PID file at `/tmp/yoink.pid`, sends a command over the socket, and exits immediately. The daemon receives the command and shows the picker panel.
3. **Without a daemon**: If no daemon is running, the binary becomes the daemon and shows the panel immediately.

This means the hotkey response is near-instant — there's no process startup overhead on each press.

## Unyoinking

Yoink keeps a stack of where each yoinked window came from. Running `yoink --unyoink` pops the most recent entry and sends that window back to its original workspace — handy when you pulled something over by mistake or are done with it.

You can bind it to a hotkey alongside the regular yoink trigger:

```toml
[mode.main.binding]
    alt-shift-ctrl-cmd-u = 'exec-and-forget /path/to/yoink --unyoink'
```

The stack is automatically cleaned up: if you manually move a yoinked window to a different workspace, it gets removed from the stack so unyoink won't try to move it again.

## How AeroSpace discovers the binary

Yoink looks for the `aerospace` CLI in these locations (in order):

1. `/opt/homebrew/bin/aerospace` (Homebrew on Apple Silicon)
2. `/usr/local/bin/aerospace` (Homebrew on Intel / manual install)

If your `aerospace` binary is elsewhere, you'll need to symlink it to one of these paths.

## Project structure

```
Sources/
  main.swift            # Daemon entry point, PID file, socket IPC
  IPC.swift             # Unix domain socket client/server
  Aerospace.swift       # AeroSpace CLI wrapper, window fetching
  AeroWindow.swift      # Window data model
  Views.swift           # Panel, cell, and row view classes
  YoinkController.swift # UI controller, search, keyboard handling
  YoinkStack.swift      # Tracks yoinked window origins for unyoink
Package.swift           # Swift Package Manager manifest
```

## License

MIT
