#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FRAMES_DIR="$ROOT/streamdeck-plugin/com.kousw.codex-pet.sdPlugin/frames"

find "$ROOT" -name ".DS_Store" -type f -delete
find "$FRAMES_DIR" -maxdepth 1 -type f \( \
  -name "*.png" -o \
  -name "*.webp" -o \
  -name "*.gif" -o \
  -name "latest-data-url.txt" -o \
  -name "status.json" \
\) -delete

echo "Removed local generated frames and .DS_Store files."
