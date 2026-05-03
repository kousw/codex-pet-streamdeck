#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_NAME="com.kousw.codex-pet.sdPlugin"
PLUGIN_TARGET="$HOME/Library/Application Support/com.elgato.StreamDeck/Plugins/$PLUGIN_NAME"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.kousw.codex-pet-capture.plist"

"$ROOT/scripts/stop-helper.sh"

if [ -L "$PLUGIN_TARGET" ]; then
  rm -f "$PLUGIN_TARGET"
  echo "Removed plugin symlink:"
  echo "  $PLUGIN_TARGET"
else
  echo "Plugin target is not a symlink, leaving it untouched:"
  echo "  $PLUGIN_TARGET"
fi

rm -f "$LAUNCH_AGENT"
echo "Removed LaunchAgent:"
echo "  $LAUNCH_AGENT"
