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

if [ ! -d "$HELPER_APP" ]; then
  "$ROOT/scripts/build-apps.sh"
fi

mkdir -p "$FRAMES_DIR"

open -W -n "$HELPER_APP" --args \
  --crop-preview-best \
  --frame-mode "$FRAME_MODE" \
  --crop-x "$CROP_X" \
  --crop-y "$CROP_Y" \
  --crop-width "$CROP_WIDTH" \
  --crop-height "$CROP_HEIGHT" \
  --output-dir "$FRAMES_DIR"

if [ ! -s "$FRAMES_DIR/crop-source.png" ] || [ ! -s "$FRAMES_DIR/crop-frame.png" ]; then
  echo "Crop preview was not generated."
  echo
  echo "Most likely cause: macOS Screen Recording permission is not granted to:"
  echo "  $HELPER_APP"
  echo
  echo "Run:"
  echo "  ./scripts/request-screen-recording.sh"
  echo
  echo "Then enable Codex Pet Capture in:"
  echo "  System Settings > Privacy & Security > Screen & System Audio Recording"
  exit 3
fi

echo "Wrote crop preview:"
echo "  $FRAMES_DIR/crop-source.png"
echo "  $FRAMES_DIR/crop-preview.png"
echo "  $FRAMES_DIR/crop-frame.png"
echo
echo "Current crop:"
echo "  CROP_X=$CROP_X CROP_Y=$CROP_Y CROP_WIDTH=$CROP_WIDTH CROP_HEIGHT=$CROP_HEIGHT"
