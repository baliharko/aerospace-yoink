#!/bin/bash
set -e

# Determine runtime directory (matches RuntimePaths.swift logic)
if [ -n "$XDG_RUNTIME_DIR" ]; then
    YOINK_DIR="$XDG_RUNTIME_DIR/yoink"
else
    YOINK_DIR="${TMPDIR:-/tmp}/yoink-$(id -u)"
fi
PID_FILE="$YOINK_DIR/yoink.pid"

# Kill running daemon so it doesn't get out of sync with the new binary
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
echo "Installed yoink to /usr/local/bin/yoink"
