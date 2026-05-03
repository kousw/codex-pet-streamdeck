# macOS Capture Helper

Native helper for discovering and eventually capturing the live Codex pet overlay.

## Build

```sh
swift build
```

For the helper used by the install script:

```sh
swift build -c release
```

## Window Probe

```sh
swift run codex-pet-capture
```

The probe prints Codex windows for bundle id `com.openai.codex`.

Observed on 2026-05-03:

- Main Codex window: layer `0`, `1586x857`, onscreen.
- Pet overlay: layer `3`, `356x320`, onscreen.
- Screen Recording permission is required before snapshot/frame output works.

## Permission

Snapshots and ScreenCaptureKit streams need macOS Screen Recording permission.

The permission is granted to the app that launches the helper. If you run the helper from Terminal, Warp, iTerm, Ghostty, or another shell app, grant Screen Recording permission to that terminal app. If Codex launches it, grant permission to Codex.

To trigger the macOS prompt:

```sh
swift run codex-pet-capture --request-screen-recording-access
```

After granting permission, restart the terminal/app that launched the helper if macOS asks for it.

If you previously denied the prompt, open:

```text
System Settings -> Privacy & Security -> Screen & System Audio Recording
```

Then enable the terminal app you are using. If it is already listed but still denied, toggle it off and on, then restart the terminal.

For the packaged helper app, macOS can keep a stale TCC entry after ad-hoc signing changes. If `status.sh` reports `screen-recording-denied` even after enabling `Codex Pet Capture`, reset that entry:

```sh
./scripts/stop-helper.sh
tccutil reset ScreenCapture com.kousw.codex-pet-capture
./scripts/request-screen-recording.sh
```

Then enable `Codex Pet Capture` again in Screen Recording settings and restart the helper. The repository also provides:

```sh
./scripts/reset-screen-recording.sh
```

For the most stable permission behavior, build once and run the binary directly from the same terminal app:

```sh
swift build
.build/debug/codex-pet-capture --request-screen-recording-access
```

## One-Shot Snapshot Probe

This is a validation path only. It uses deprecated CoreGraphics snapshot APIs so we can quickly prove target selection. The durable capture path should use ScreenCaptureKit.

```sh
swift run codex-pet-capture --snapshot-best --output /tmp/codex-pet-streamdeck/probe.png
```

Or target a specific window:

```sh
swift run codex-pet-capture --snapshot-window-id 26482 --output /tmp/codex-pet-streamdeck/pet-overlay.png
```

## ScreenCaptureKit Snapshot Probe

This is the preferred one-shot validation path before implementing a continuous stream.

```sh
swift run codex-pet-capture --sck-snapshot-best --output /tmp/codex-pet-streamdeck/sck-probe.png
```

Or target a specific window:

```sh
swift run codex-pet-capture --sck-snapshot-window-id 26482 --output /tmp/codex-pet-streamdeck/sck-pet-overlay.png
```

Validated behavior:

- ScreenCaptureKit can capture the Codex pet overlay window directly.
- The overlay capture includes transparent-window content composited on black by the current PNG path.
- This is still better than full main-window capture because the source image is only about `356x320`.

## Stream Deck Frame Probe

Render a `144x144` Stream Deck-ready frame from the overlay window.

```sh
swift run codex-pet-capture --sck-frame-best --frame-mode pet --output /tmp/codex-pet-streamdeck/latest.png
```

Available modes:

- `pet`
- `pet-with-bubble`
- `debug-wide`

You can also target a specific window with `--sck-frame-window-id <windowID>`.

Validated outputs:

- `pet`: creates a mascot-focused `144x144` PNG and removes neutral white/gray UI surfaces from the crop.
- `pet-with-bubble`: fits the whole overlay into `144x144`; useful for debugging but probably too small for normal key use.

`pet` mode uses crop-only rendering to preserve the character pixels. It does not run color-key cleanup because that can damage the pet artwork.

## Short Publisher Probe

Write `latest.png` and `status.json` repeatedly for a bounded duration.

```sh
swift run codex-pet-capture --publish-best --frame-mode pet --capture-engine core-graphics --fps 8 --duration 3
```

You can also target a specific window with `--publish-window-id <windowID>`, but `--publish-best` should prefer the small layer `3` pet overlay window.

This is still a milestone transport, not the final performance target. It is useful for proving the Stream Deck plugin frame reader before replacing polling with a push channel.

Capture engines:

- `core-graphics`: current default for the short publisher because it behaves reliably for repeated one-shot captures.
- `screen-capture-kit`: keep for one-shot validation; repeated snapshots should move to a real `SCStream` before becoming the steady-state path.

## Service Mode

`--serve` is the current local runtime path. It repeatedly discovers the best Codex pet overlay window, captures it, renders a Stream Deck frame, and writes:

- `latest.png`
- `latest-data-url.txt`
- `frame-<slot>.png`
- `status.json`

Use it for manual testing:

```sh
swift run codex-pet-capture \
  --serve \
  --frame-mode pet \
  --capture-engine core-graphics \
  --fps 1 \
  --output-dir ../streamdeck-plugin/com.kousw.codex-pet.sdPlugin/frames
```

Important flags:

- `--fps <number>`: clamped to `1...15`; default is `1`.
- `--retry-interval <seconds>`: delay before trying again when no Codex overlay is found or capture fails; default is `2`.
- `--duration <seconds>`: optional bounded run for tests.
- `--bundle-id <id>`: defaults to `com.openai.codex`.
- `--crop-x <number>`, `--crop-y <number>`, `--crop-width <number>`, `--crop-height <number>`: pet crop rectangle in the `356x320` overlay reference coordinate space. The renderer scales these values to the actual captured window size.

Service mode intentionally reselects the overlay instead of holding one window ID forever. Codex may recreate the overlay window when the pet is hidden, shown, or the app is relaunched.

## Installed Configuration

The LaunchAgent wrapper reads:

```text
~/Library/Application Support/Codex Pet StreamDeck/config.env
```

Example:

```sh
FPS="5"
RETRY_INTERVAL="2"
FRAME_MODE="pet"
CAPTURE_ENGINE="core-graphics"
CROP_X="248"
CROP_Y="222"
CROP_WIDTH="89"
CROP_HEIGHT="89"
```

The menu bar app exposes FPS presets and simple crop nudges. Use `Open Config File` for arbitrary values.

For visual tuning, open `Settings > Crop Tuner` from the menu bar app. It renders:

- `crop-preview.png`: overlay snapshot with the active crop rectangle.
- `crop-frame.png`: the resulting `144x144` Stream Deck frame.

The same preview can be generated from the repository root:

```sh
./scripts/preview-crop.sh
```
