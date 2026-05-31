#!/usr/bin/env bash
set -euo pipefail

LABEL="com.kousw.codex-pet-renderer"
OLD_LABEL="com.kousw.codex-pet-capture"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
OLD_LAUNCH_AGENT="$HOME/Library/LaunchAgents/$OLD_LABEL.plist"
CAPTURE_PROCESS="codex-pet-capture"
RENDER_PROCESS="codex-pet-renderer"

if [ -f "$LAUNCH_AGENT" ]; then
  launchctl bootout "gui/$UID" "$LAUNCH_AGENT" >/dev/null 2>&1 || true
fi
if [ -f "$OLD_LAUNCH_AGENT" ]; then
  launchctl bootout "gui/$UID" "$OLD_LAUNCH_AGENT" >/dev/null 2>&1 || true
fi
pkill -f "$CAPTURE_PROCESS" >/dev/null 2>&1 || true
pkill -f "$RENDER_PROCESS" >/dev/null 2>&1 || true

echo "Stopped $LABEL"
