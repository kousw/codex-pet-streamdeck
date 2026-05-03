#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
CAPTURE_APP="$DIST/Codex Pet Capture.app"
MENUBAR_APP="$DIST/Codex Pet.app"
CAPTURE_BIN="$ROOT/capture-macos/.build/release/codex-pet-capture"
MENUBAR_BIN="$ROOT/capture-macos/.build/release/codex-pet-menubar"
BUILD_MODE="${1:-all}"

case "$BUILD_MODE" in
  all)
    swift build -c release --package-path "$ROOT/capture-macos"
    ;;
  --menubar-only)
    swift build -c release --package-path "$ROOT/capture-macos" --product codex-pet-menubar
    ;;
  --capture-only)
    swift build -c release --package-path "$ROOT/capture-macos" --product codex-pet-capture
    ;;
  *)
    echo "Usage: ./scripts/build-apps.sh [--menubar-only|--capture-only]"
    exit 1
    ;;
esac

make_app() {
  local app_path="$1"
  local executable_path="$2"
  local executable_name="$3"
  local bundle_id="$4"
  local bundle_name="$5"
  local usage="$6"
  local plist_tmp
  local existing_executable="$app_path/Contents/MacOS/$executable_name"
  local existing_plist="$app_path/Contents/Info.plist"

  plist_tmp="$(mktemp)"
  cat > "$plist_tmp" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$executable_name</string>
  <key>CFBundleIdentifier</key>
  <string>$bundle_id</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$bundle_name</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSScreenCaptureUsageDescription</key>
  <string>$usage</string>
</dict>
</plist>
PLIST

  if [ -x "$existing_executable" ] &&
    [ -f "$existing_plist" ] &&
    cmp -s "$executable_path" "$existing_executable" &&
    cmp -s "$plist_tmp" "$existing_plist"; then
    rm -f "$plist_tmp"
    echo "Unchanged app bundle, preserving TCC identity: $app_path"
    return
  fi

  rm -rf "$app_path"
  mkdir -p "$app_path/Contents/MacOS"
  cp "$executable_path" "$existing_executable"
  chmod +x "$existing_executable"
  mv "$plist_tmp" "$existing_plist"
  codesign --force --deep --sign - "$app_path"
}

mkdir -p "$DIST"

if [ "$BUILD_MODE" = "all" ] || [ "$BUILD_MODE" = "--capture-only" ]; then
  make_app \
    "$CAPTURE_APP" \
    "$CAPTURE_BIN" \
    "codex-pet-capture" \
    "com.kousw.codex-pet-capture" \
    "Codex Pet Capture" \
    "Codex Pet Capture needs Screen Recording permission to mirror the Codex pet overlay to Stream Deck."
fi

if [ "$BUILD_MODE" = "all" ] || [ "$BUILD_MODE" = "--menubar-only" ]; then
  make_app \
    "$MENUBAR_APP" \
    "$MENUBAR_BIN" \
    "codex-pet-menubar" \
    "com.kousw.codex-pet-menubar" \
    "Codex Pet" \
    "Codex Pet may open helper tools that need Screen Recording permission."
fi

if [ "$BUILD_MODE" = "all" ] || [ "$BUILD_MODE" = "--capture-only" ]; then
  echo "$CAPTURE_APP"
fi
if [ "$BUILD_MODE" = "all" ] || [ "$BUILD_MODE" = "--menubar-only" ]; then
  echo "$MENUBAR_APP"
fi
