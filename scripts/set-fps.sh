#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
echo "Usage: ./scripts/set-fps.sh <fps>"
  echo "Example: ./scripts/set-fps.sh 10"
  echo "Allowed range: 1..15"
  exit 1
fi

REQUESTED_FPS="$1"
case "$REQUESTED_FPS" in
  ''|*[!0-9.]*)
    echo "FPS must be a number between 1 and 15."
    exit 1
    ;;
esac

awk -v fps="$REQUESTED_FPS" 'BEGIN { if (fps < 1 || fps > 15) exit 1 }' || {
  echo "FPS must be between 1 and 15."
  exit 1
}

CONFIG_DIR="$HOME/Library/Application Support/Codex Pet StreamDeck"
CONFIG_FILE="$CONFIG_DIR/config.env"
mkdir -p "$CONFIG_DIR"

RETRY_INTERVAL="2"
HELPER_MODE="render-assets"
RENDERER_ENGINE="rust"
DEBUG="0"
PET_ID=""
PET_STATE=""
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

cat > "$CONFIG_FILE" <<CONFIG
FPS="$REQUESTED_FPS"
RETRY_INTERVAL="$RETRY_INTERVAL"
HELPER_MODE="$HELPER_MODE"
RENDERER_ENGINE="$RENDERER_ENGINE"
DEBUG="$DEBUG"
PET_ID="$PET_ID"
PET_STATE="$PET_STATE"
FRAME_MODE="$FRAME_MODE"
CAPTURE_ENGINE="$CAPTURE_ENGINE"
CROP_X="$CROP_X"
CROP_Y="$CROP_Y"
CROP_WIDTH="$CROP_WIDTH"
CROP_HEIGHT="$CROP_HEIGHT"
CONFIG

echo "Set capture FPS to $REQUESTED_FPS."
echo "Restart the helper to apply it:"
echo "  ./scripts/stop-helper.sh"
echo "  ./scripts/start-helper.sh"
