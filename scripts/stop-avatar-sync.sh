#!/usr/bin/env bash
set -euo pipefail

LABEL="com.kousw.codex-pet-avatar-sync"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$UID" "$LAUNCH_AGENT" >/dev/null 2>&1 || true
pkill -f "sync-codex-avatar-frame.js" >/dev/null 2>&1 || true

echo "Stopped $LABEL"
