# Codex Pet Stream Deck

Mirror the live Codex app pet overlay onto an Elgato Stream Deck key.

This project captures the small macOS overlay window rendered by the Codex desktop app, crops it to the pet, writes a Stream Deck-ready frame, and lets a Stream Deck plugin display that frame on a key.

## Demo

[![Codex Pet Stream Deck demo](docs/assets/demo-poster.png)](docs/assets/demo.mp4)

## Status

This is usable as a local preview, but it is not packaged as a polished public release yet.

- Works on macOS with the Codex desktop app and Elgato Stream Deck.
- Uses a native Swift helper for capture.
- Uses a Stream Deck SDK plugin for display.
- Defaults to `1fps` for reliability. The Stream Deck plugin reads the helper's `status.json` and automatically adjusts its polling interval to the configured capture FPS.
- Uses CoreGraphics window snapshots for the current steady-state path. This API is deprecated, but it is currently more stable for this PoC than repeated ScreenCaptureKit one-shot captures.

## Requirements

- macOS 14 or newer.
- Swift 6 toolchain.
- Codex desktop app.
- Elgato Stream Deck app 6.5 or newer.
- macOS Screen Recording permission for the capture helper or the app that launches it.

## Build From Source

From the repository root:

```sh
./scripts/install.sh
./scripts/request-screen-recording.sh
./scripts/start-helper.sh
./scripts/open-menubar.sh
```

`install.sh` builds the Swift app bundles, symlinks the Stream Deck plugin into Stream Deck's plugin folder, creates the user LaunchAgent, and writes the default config file. Keep the repository in a stable path after installing because the LaunchAgent points back to this checkout.

Then restart the Stream Deck app and add `Codex > Live Pet` to a key. The menu bar controller can start, stop, restart, tune crop, and inspect the helper without returning to a terminal.

Expected local artifacts:

```text
dist/Codex Pet Capture.app
dist/Codex Pet.app
~/Library/LaunchAgents/com.kousw.codex-pet-capture.plist
~/Library/Application Support/Codex Pet StreamDeck/config.env
~/Library/Application Support/com.elgato.StreamDeck/Plugins/com.kousw.codex-pet.sdPlugin
```

To verify capture before debugging Stream Deck, run:

```sh
./scripts/status.sh
open streamdeck-plugin/com.kousw.codex-pet.sdPlugin/frames/latest.png
```

If `status.sh` reports `status: "ok"` and `latest.png` shows the pet, the capture helper is working. If the Stream Deck key still does not update, remove and re-add the `Live Pet` action and restart the Stream Deck app.

If macOS blocks capture, open:

```text
System Settings > Privacy & Security > Screen & System Audio Recording
```

Grant access to the helper process if it appears there. If you are running the helper manually from Terminal, Ghostty, iTerm, Warp, or another shell, grant access to that shell app and restart it if macOS asks.

For the normal installed path, grant access to `Codex Pet Capture`. It is generated under `dist/Codex Pet Capture.app` so macOS can show it as an app in the Screen Recording permission list.

If you rebuild the app bundles, macOS may treat the ad-hoc signed helper as changed. Re-run `./scripts/request-screen-recording.sh`, toggle `Codex Pet Capture` off/on in Screen Recording settings if needed, then restart the helper.

If `status.sh` still reports `screen-recording-denied` after granting access, reset the TCC entry for the capture helper:

```sh
./scripts/stop-helper.sh
tccutil reset ScreenCapture com.kousw.codex-pet-capture
./scripts/request-screen-recording.sh
```

Then enable `Codex Pet Capture` again in Screen Recording settings and restart the helper. The same flow is wrapped by:

```sh
./scripts/reset-screen-recording.sh
```

During local development, avoid rebuilding `Codex Pet Capture.app` unless capture code changed. macOS ties Screen Recording permission to the helper app's code identity, and ad-hoc signed rebuilds can invalidate that permission. `build-apps.sh` preserves an unchanged app bundle so menu bar-only changes do not normally require granting Screen Recording again.

When only the menu bar UI changed, build just that app:

```sh
./scripts/build-apps.sh --menubar-only
```

Use the full build only when the capture helper changed:

```sh
./scripts/build-apps.sh
```

## Manual Test

Run the helper directly for a short test:

```sh
cd capture-macos
swift run codex-pet-capture \
  --serve \
  --frame-mode pet \
  --capture-engine core-graphics \
  --fps 1 \
  --duration 10 \
  --output-dir ../streamdeck-plugin/com.kousw.codex-pet.sdPlugin/frames
```

The generated frame should appear at:

```text
streamdeck-plugin/com.kousw.codex-pet.sdPlugin/frames/latest.png
```

## Helper Control

```sh
./scripts/start-helper.sh
./scripts/stop-helper.sh
./scripts/status.sh
./scripts/open-menubar.sh
./scripts/request-screen-recording.sh
./scripts/reset-screen-recording.sh
./scripts/set-fps.sh 1
./scripts/clean-artifacts.sh
./scripts/uninstall.sh
```

`status.sh` prints the LaunchAgent state, the latest frame status, and recent helper errors.

Capture FPS is configurable. The default is `1` for Stream Deck plugin stability, but other integrations can raise it:

```sh
./scripts/set-fps.sh 5
./scripts/stop-helper.sh
./scripts/start-helper.sh
```

The helper clamps fps to `1...15`.

The menu bar controller appears as `Codex Pet` in the macOS menu bar. It provides:

- helper start, stop, and restart
- latest frame status
- capture FPS presets
- crop adjustment for pets that do not fit the default frame
- a crop tuner window with an overlay preview and the resulting `144x144` Stream Deck frame
- quick access to the frames and Stream Deck plugin folders
- quick access to the config file
- a best-effort `codex://` launcher

The installed config lives at:

```text
~/Library/Application Support/Codex Pet StreamDeck/config.env
```

Supported settings:

```sh
FPS="1"
RETRY_INTERVAL="2"
FRAME_MODE="pet"
CAPTURE_ENGINE="core-graphics"
CROP_X="248"
CROP_Y="222"
CROP_WIDTH="89"
CROP_HEIGHT="89"
```

`FPS` is clamped to `1...15`. The menu bar app can update FPS and crop values, then restarts the helper so the change takes effect.

For visual crop tuning, open:

```text
Codex Pet menu bar icon > Settings > Crop Tuner
```

Or open the tuner directly:

```sh
./scripts/open-crop-tuner.sh
```

The tuner shows the current overlay with a red crop rectangle and the resulting Stream Deck frame. Changing X/Y/Width/Height updates the preview. Press `Save & Restart Helper` when the frame looks right.

You can also generate the same preview from the terminal:

```sh
./scripts/preview-crop.sh
```

It writes:

```text
streamdeck-plugin/com.kousw.codex-pet.sdPlugin/frames/crop-preview.png
streamdeck-plugin/com.kousw.codex-pet.sdPlugin/frames/crop-frame.png
```

## Troubleshooting

If the Stream Deck key does not change, remove and re-add the `Live Pet` action. Stream Deck may ignore plugin `setImage` calls when the key has a user-customized image.

If frames stop updating, run:

```sh
./scripts/status.sh
```

Common causes are missing Screen Recording permission, Codex not showing the pet overlay, or the Stream Deck app needing a restart after plugin changes.

If the pet is visible in `latest.png` but not on the key, the capture helper is working and the issue is likely in the Stream Deck plugin/runtime side.

## Project Layout

- `capture-macos/`: native Swift capture helper.
- `streamdeck-plugin/`: Stream Deck plugin.
- `shared/`: frame/status contract.
- `docs/`: research, architecture, and release notes.

## Docs

- [Research notes](docs/research.md)
- [Architecture](docs/architecture.md)
- [Public readiness](docs/public-readiness.md)
- [Security review](docs/security-review.md)
