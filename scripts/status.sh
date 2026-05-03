#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATUS="$ROOT/streamdeck-plugin/com.kousw.codex-pet.sdPlugin/frames/status.json"
LOG_DIR="$HOME/Library/Logs/codex-pet-streamdeck"
CONFIG_FILE="$HOME/Library/Application Support/Codex Pet StreamDeck/config.env"

echo "Config:"
if [ -f "$CONFIG_FILE" ]; then
  cat "$CONFIG_FILE"
else
  echo "  missing: $CONFIG_FILE"
fi

echo

echo "Helper status:"
launchctl print "gui/$UID/com.kousw.codex-pet-capture" 2>/dev/null | sed -n '1,80p' || echo "  not loaded"

echo
echo "Frame status:"
if [ -f "$STATUS" ]; then
  cat "$STATUS"
  echo
else
  echo "  missing: $STATUS"
fi

echo
echo "Recent helper errors:"
if [ -f "$LOG_DIR/helper.err.log" ]; then
  if [ -f "$STATUS" ]; then
    STATUS_MTIME="$(stat -f %m "$STATUS")"
    ERROR_MTIME="$(stat -f %m "$LOG_DIR/helper.err.log")"
    if [ "$ERROR_MTIME" -le "$STATUS_MTIME" ]; then
      echo "  no newer helper errors since the latest frame status"
      echo "  helper.err.log may contain stale errors from earlier permission attempts"
      exit 0
    fi
  fi

  tail -n 40 "$LOG_DIR/helper.err.log"
else
  echo "  no helper.err.log yet"
fi
