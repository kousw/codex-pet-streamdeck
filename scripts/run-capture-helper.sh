#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_DIR="$HOME/Library/Application Support/Codex Pet StreamDeck"
CONFIG_FILE="$CONFIG_DIR/config.env"
HELPER_APP="$ROOT/dist/Codex Pet Capture.app"
FRAMES_DIR="$ROOT/streamdeck-plugin/com.kousw.codex-pet.sdPlugin/frames"

FPS="1"
RETRY_INTERVAL="2"
FRAME_MODE="pet"
CAPTURE_ENGINE="core-graphics"
CROP_X="248"
CROP_Y="222"
CROP_WIDTH="89"
CROP_HEIGHT="89"

if [ -f "$CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

mkdir -p "$FRAMES_DIR"

open -W -n "$HELPER_APP" --args \
  --serve \
  --frame-mode "$FRAME_MODE" \
  --capture-engine "$CAPTURE_ENGINE" \
  --fps "$FPS" \
  --retry-interval "$RETRY_INTERVAL" \
  --crop-x "$CROP_X" \
  --crop-y "$CROP_Y" \
  --crop-width "$CROP_WIDTH" \
  --crop-height "$CROP_HEIGHT" \
  --output-dir "$FRAMES_DIR"
