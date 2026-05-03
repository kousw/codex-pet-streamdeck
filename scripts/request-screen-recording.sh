#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Codex Pet Capture.app"
BINARY="$APP/Contents/MacOS/codex-pet-capture"

if [ ! -x "$BINARY" ]; then
  "$ROOT/scripts/build-apps.sh"
fi

open -W -n "$APP" --args --request-screen-recording-access
