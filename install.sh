#!/bin/bash
set -e
# Work from the repo root no matter where the script is run from
cd "$(dirname "$0")"

PLIST_NAME="com.yoink.daemon"
PLIST_SRC="$PWD/$PLIST_NAME.plist"
PLIST_DST="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

# Build before touching the running daemon, so a failed build leaves it running
swift build -c release

# Stop running daemon (LaunchAgent or legacy PID-based)
launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true

if [ -n "$XDG_RUNTIME_DIR" ]; then
    YOINK_DIR="$XDG_RUNTIME_DIR/yoink"
else
    YOINK_DIR="${TMPDIR:-/tmp}/yoink-$(id -u)"
fi
PID_FILE="$YOINK_DIR/yoink.pid"
if [ -f "$PID_FILE" ]; then
    rm -f "$PID_FILE" "$YOINK_DIR/yoink.sock"
fi
# Kill any remaining yoink processes (manual launches, stale daemons, etc.)
pkill -x yoink 2>/dev/null && echo "Stopped running yoink process(es)" || true
sleep 0.5

sudo mkdir -p /usr/local/bin
sudo cp .build/release/yoink /usr/local/bin/yoink
sudo codesign --force --sign - /usr/local/bin/yoink
echo "Installed yoink to /usr/local/bin/yoink"

# Install and start LaunchAgent
mkdir -p "$(dirname "$PLIST_DST")"
cp "$PLIST_SRC" "$PLIST_DST"
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
echo "Started yoink daemon via LaunchAgent"
