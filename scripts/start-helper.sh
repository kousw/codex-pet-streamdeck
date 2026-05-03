#!/usr/bin/env bash
set -euo pipefail

LABEL="com.kousw.codex-pet-capture"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
CAPTURE_PROCESS="codex-pet-capture"

if [ ! -f "$LAUNCH_AGENT" ]; then
  echo "LaunchAgent is not installed:"
  echo "  $LAUNCH_AGENT"
  echo "Run ./scripts/install.sh first."
  exit 1
fi

launchctl bootout "gui/$UID" "$LAUNCH_AGENT" >/dev/null 2>&1 || true
pkill -f "$CAPTURE_PROCESS" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$LAUNCH_AGENT"
launchctl kickstart -k "gui/$UID/$LABEL"

echo "Started $LABEL"
