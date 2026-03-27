#!/bin/bash
set -e

PLIST_NAME="com.yoink.daemon"
PLIST_SRC="$(cd "$(dirname "$0")" && pwd)/$PLIST_NAME.plist"
PLIST_DST="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

# Stop running daemon (LaunchAgent or legacy PID-based)
launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true

if [ -n "$XDG_RUNTIME_DIR" ]; then
    YOINK_DIR="$XDG_RUNTIME_DIR/yoink"
else
    YOINK_DIR="${TMPDIR:-/tmp}/yoink-$(id -u)"
fi
PID_FILE="$YOINK_DIR/yoink.pid"
if [ -f "$PID_FILE" ]; then
    pid=$(head -1 "$PID_FILE" | tr -d '[:space:]')
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo "Stopping running yoink daemon (PID $pid)..."
        kill "$pid"
    fi
    rm -f "$PID_FILE" "$YOINK_DIR/yoink.sock"
fi

swift build -c release
sudo cp .build/release/yoink /usr/local/bin/yoink
sudo codesign --force --sign - /usr/local/bin/yoink
echo "Installed yoink to /usr/local/bin/yoink"

# Install and start LaunchAgent
cp "$PLIST_SRC" "$PLIST_DST"
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
echo "Started yoink daemon via LaunchAgent"
