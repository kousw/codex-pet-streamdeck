#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_NAME="com.kousw.codex-pet.sdPlugin"
PLUGIN_SOURCE="$ROOT/streamdeck-plugin/$PLUGIN_NAME"
PLUGIN_TARGET_DIR="$HOME/Library/Application Support/com.elgato.StreamDeck/Plugins"
PLUGIN_TARGET="$PLUGIN_TARGET_DIR/$PLUGIN_NAME"
LABEL="com.kousw.codex-pet-renderer"
OLD_LABEL="com.kousw.codex-pet-capture"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
OLD_LAUNCH_AGENT="$HOME/Library/LaunchAgents/$OLD_LABEL.plist"
HELPER_RUNNER="$ROOT/scripts/internal/run-capture-helper.sh"
FRAMES_DIR="$PLUGIN_SOURCE/frames"
LOG_DIR="$HOME/Library/Logs/codex-pet-streamdeck"
CONFIG_DIR="$HOME/Library/Application Support/Codex Pet StreamDeck"
CONFIG_FILE="$CONFIG_DIR/config.env"

mkdir -p "$PLUGIN_TARGET_DIR" "$FRAMES_DIR" "$LOG_DIR" "$CONFIG_DIR"

echo "Building Rust renderer..."
cargo build --release --manifest-path "$ROOT/renderer-rust/Cargo.toml"

if [ -L "$PLUGIN_TARGET" ] || [ ! -e "$PLUGIN_TARGET" ]; then
  rm -f "$PLUGIN_TARGET"
  ln -s "$PLUGIN_SOURCE" "$PLUGIN_TARGET"
else
  echo "Refusing to replace existing non-symlink plugin at:"
  echo "  $PLUGIN_TARGET"
  exit 1
fi

FPS="10"
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
FPS="$FPS"
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

mkdir -p "$(dirname "$LAUNCH_AGENT")"
launchctl bootout "gui/$UID" "$OLD_LAUNCH_AGENT" >/dev/null 2>&1 || true
rm -f "$OLD_LAUNCH_AGENT"
cat > "$LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$HELPER_RUNNER</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/helper.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/helper.err.log</string>
</dict>
</plist>
PLIST

echo "Installed Stream Deck plugin symlink:"
echo "  $PLUGIN_TARGET"
echo "Installed LaunchAgent:"
echo "  $LAUNCH_AGENT"
echo "Installed config:"
echo "  $CONFIG_FILE"
echo
echo "Next:"
echo "  ./scripts/start-helper.sh"
echo "  ./scripts/set-fps.sh 10"
echo "  Restart Stream Deck, then add the Codex > Live Pet action."
echo
echo "The default asset-renderer mode does not need Screen Recording permission."
echo "Legacy Swift capture-overlay mode is documented in capture-macos/README.md."
