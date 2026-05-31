#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: ./scripts/set-debug.sh <0|1>"
  echo "Example: ./scripts/set-debug.sh 1"
  exit 1
fi

case "$1" in
  0|1|true|false)
    REQUESTED_DEBUG="$1"
    ;;
  *)
    echo "Debug must be 0, 1, true, or false."
    exit 1
    ;;
esac

CONFIG_DIR="$HOME/Library/Application Support/Codex Pet StreamDeck"
CONFIG_FILE="$CONFIG_DIR/config.env"
mkdir -p "$CONFIG_DIR"

FPS="10"
RETRY_INTERVAL="2"
HELPER_MODE="render-assets"
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

DEBUG="$REQUESTED_DEBUG"

cat > "$CONFIG_FILE" <<CONFIG
FPS="$FPS"
RETRY_INTERVAL="$RETRY_INTERVAL"
HELPER_MODE="$HELPER_MODE"
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

echo "Set debug logging to $DEBUG."
echo "Restart the helper to apply it:"
echo "  ./scripts/stop-helper.sh"
echo "  ./scripts/start-helper.sh"
