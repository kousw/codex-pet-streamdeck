#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG_DIR="$HOME/Library/Application Support/Codex Pet StreamDeck"
CONFIG_FILE="$CONFIG_DIR/config.env"
HELPER_APP="$ROOT/dist/Codex Pet Capture.app"
HELPER_BINARY="$HELPER_APP/Contents/MacOS/codex-pet-capture"
RUST_RENDERER="$ROOT/renderer-rust/target/release/codex-pet-renderer"
FRAMES_DIR="$ROOT/streamdeck-plugin/com.kousw.codex-pet.sdPlugin/frames"

FPS="10"
RETRY_INTERVAL="2"
HELPER_MODE="render-assets"
RENDERER_ENGINE="rust"
DEBUG="0"
FRAME_MODE="pet"
CAPTURE_ENGINE="core-graphics"
CROP_X="248"
CROP_Y="222"
CROP_WIDTH="89"
CROP_HEIGHT="89"
PET_ID=""
PET_STATE=""

if [ -f "$CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

mkdir -p "$FRAMES_DIR"

if [ "$HELPER_MODE" = "capture-overlay" ]; then
  ARGS=(
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
  )

  if [ "$DEBUG" = "1" ] || [ "$DEBUG" = "true" ]; then
    ARGS+=(--debug)
  fi

  open -W -n "$HELPER_APP" --args "${ARGS[@]}"
elif [ "$RENDERER_ENGINE" = "swift" ]; then
  ARGS=(
    --render-assets
    --fps "$FPS"
    --retry-interval "$RETRY_INTERVAL"
    --output-dir "$FRAMES_DIR"
  )

  if [ -n "$PET_ID" ]; then
    ARGS+=(--pet-id "$PET_ID")
  fi

  if [ -n "$PET_STATE" ]; then
    ARGS+=(--pet-state "$PET_STATE")
  fi

  if [ "$DEBUG" = "1" ] || [ "$DEBUG" = "true" ]; then
    ARGS+=(--debug)
  fi

  "$HELPER_BINARY" "${ARGS[@]}"
else
  if [ ! -x "$RUST_RENDERER" ]; then
    echo "Missing Rust renderer binary:"
    echo "  $RUST_RENDERER"
    echo "Run ./scripts/install.sh or cargo build --release in renderer-rust."
    exit 1
  fi

  ARGS=(
    --fps "$FPS"
    --retry-interval "$RETRY_INTERVAL"
    --output-dir "$FRAMES_DIR"
  )

  if [ -n "$PET_ID" ]; then
    ARGS+=(--pet-id "$PET_ID")
  fi

  if [ -n "$PET_STATE" ]; then
    ARGS+=(--pet-state "$PET_STATE")
  fi

  if [ "$DEBUG" = "1" ] || [ "$DEBUG" = "true" ]; then
    ARGS+=(--debug)
  fi

  "$RUST_RENDERER" "${ARGS[@]}"
fi
