#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.kousw.codex-pet-avatar-sync"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/codex-pet-streamdeck"
NODE_BIN="$(command -v node)"
PORT="${1:-9222}"

mkdir -p "$(dirname "$LAUNCH_AGENT")" "$LOG_DIR"

cat > "$LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$NODE_BIN</string>
    <string>$ROOT/scripts/sync-codex-avatar-frame.js</string>
    <string>$PORT</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/avatar-sync.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/avatar-sync.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$UID" "$LAUNCH_AGENT" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$LAUNCH_AGENT"
launchctl kickstart -k "gui/$UID/$LABEL"

echo "Started $LABEL on DevTools port $PORT"
echo "Logs:"
echo "  $LOG_DIR/avatar-sync.log"
echo "  $LOG_DIR/avatar-sync.err.log"
