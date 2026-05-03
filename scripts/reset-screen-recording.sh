#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT/scripts/stop-helper.sh"
tccutil reset ScreenCapture com.kousw.codex-pet-capture
"$ROOT/scripts/request-screen-recording.sh"

cat <<'TEXT'
Reset Screen Recording permission for Codex Pet Capture.

Next:
  1. Open System Settings > Privacy & Security > Screen & System Audio Recording.
  2. Enable Codex Pet Capture.
  3. Restart the helper:
       ./scripts/start-helper.sh
       ./scripts/status.sh
TEXT
