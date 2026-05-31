#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="$ROOT/dist/Codex Pet.app"
BINARY="$APP/Contents/MacOS/codex-pet-menubar"

if [ ! -x "$BINARY" ]; then
  "$ROOT/scripts/dev/build-apps.sh"
fi

open -n "$APP"
echo "Opened Codex Pet menu bar controller."
