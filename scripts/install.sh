#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_NAME="com.kousw.codex-pet.sdPlugin"
PLUGIN_SOURCE="$ROOT/streamdeck-plugin/$PLUGIN_NAME"
PLUGIN_TARGET_DIR="$HOME/Library/Application Support/com.elgato.StreamDeck/Plugins"
PLUGIN_TARGET="$PLUGIN_TARGET_DIR/$PLUGIN_NAME"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.kousw.codex-pet-capture.plist"
HELPER_RUNNER="$ROOT/scripts/run-capture-helper.sh"
FRAMES_DIR="$PLUGIN_SOURCE/frames"
LOG_DIR="$HOME/Library/Logs/codex-pet-streamdeck"
CONFIG_DIR="$HOME/Library/Application Support/Codex Pet StreamDeck"
CONFIG_FILE="$CONFIG_DIR/config.env"

mkdir -p "$PLUGIN_TARGET_DIR" "$FRAMES_DIR" "$LOG_DIR" "$CONFIG_DIR"

echo "Building macOS app bundles..."
"$ROOT/scripts/build-apps.sh"

if [ -L "$PLUGIN_TARGET" ] || [ ! -e "$PLUGIN_TARGET" ]; then
  rm -f "$PLUGIN_TARGET"
  ln -s "$PLUGIN_SOURCE" "$PLUGIN_TARGET"
else
  echo "Refusing to replace existing non-symlink plugin at:"
  echo "  $PLUGIN_TARGET"
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" <<CONFIG
FPS="1"
RETRY_INTERVAL="2"
FRAME_MODE="pet"
CAPTURE_ENGINE="core-graphics"
CROP_X="248"
CROP_Y="222"
CROP_WIDTH="89"
CROP_HEIGHT="89"
CONFIG
fi

mkdir -p "$(dirname "$LAUNCH_AGENT")"
cat > "$LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.kousw.codex-pet-capture</string>
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
echo "  ./scripts/open-menubar.sh"
echo "  ./scripts/set-fps.sh 1"
echo "  Restart Stream Deck, then add the Codex > Live Pet action."
echo
echo "If macOS blocks capture, grant Screen Recording to the helper launcher in"
echo "System Settings > Privacy & Security > Screen & System Audio Recording."
echo
echo "If Codex Pet Capture is not listed there yet, run:"
echo "  ./scripts/request-screen-recording.sh"
