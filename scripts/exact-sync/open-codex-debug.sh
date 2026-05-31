#!/usr/bin/env bash
set -euo pipefail

PORT="${1:-9222}"

osascript -e 'tell application "Codex" to quit' >/dev/null 2>&1 || true
sleep 1

open -na "Codex" --args "--remote-debugging-port=$PORT"

echo "Opened Codex with Electron remote debugging on port $PORT."
echo "Verify with:"
echo "  curl http://127.0.0.1:$PORT/json/version"
