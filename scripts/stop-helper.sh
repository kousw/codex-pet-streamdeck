#!/usr/bin/env bash
set -euo pipefail

LABEL="com.kousw.codex-pet-capture"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
CAPTURE_PROCESS="codex-pet-capture"

if [ -f "$LAUNCH_AGENT" ]; then
  launchctl bootout "gui/$UID" "$LAUNCH_AGENT" >/dev/null 2>&1 || true
fi
pkill -f "$CAPTURE_PROCESS" >/dev/null 2>&1 || true

echo "Stopped $LABEL"
