# Architecture

Date: 2026-05-03

## Position

The original architecture was sound for the first proof of concept if we treat
it as a live frame pipeline, not as a pet asset converter.

The core product should be:

```text
Codex overlay/window -> macOS capture helper -> frame transport -> Stream Deck plugin -> setImage
```

Update, 2026-05-31: the preferred next architecture is no longer capture-first.
The capture pipeline should remain as a fallback, but the default path should
move toward local asset rendering:

```text
Codex local state + pet spritesheet -> asset renderer -> frame transport -> Stream Deck plugin -> setImage
```

For exact live motion, an optional local DevTools bridge can read the Codex
overlay's current sprite row/column and notification badge count when Codex is
launched with `--remote-debugging-port`. That bridge writes the same
`~/.codex/pet-streamdeck-state.json` override consumed by the Swift renderer.

See [Asset renderer migration](asset-renderer-migration.md). That plan is
informed by [lkuczborski/WatchPet](https://github.com/lkuczborski/WatchPet),
which renders Codex pet spritesheets on Apple Watch through a local bridge
instead of streaming captured pixels.

The important design choice is to keep the capture implementation, frame delivery, and Stream Deck action logic separate from the start. The first prototype can be small, but it should still respect these boundaries.

## Design Principles

- Render local pet assets by default; use capture only as a fallback for exact rendered output.
- Keep Codex app internals as diagnostics only; DOM selectors and bundle filenames are not stable APIs.
- Treat Electron remote-debugging sync as an optional developer feature, not as the default public path.
- Make the capture helper independently runnable and debuggable.
- Make the Stream Deck plugin consume frames through a narrow interface.
- Prefer replaceable transport over tightly coupling the plugin to the capture implementation.
- Start with conservative frame rates and explicit failure states.

## Components

### `capture-macos`

Owns all macOS-specific capture work.

Responsibilities:

- Discover Codex windows for bundle id `com.openai.codex`.
- Choose the target window or capture region.
- Capture frames with ScreenCaptureKit once the target model is known.
- Crop to the selected view mode.
- Encode the Stream Deck-ready frame.
- Publish health/status information.

Non-responsibilities:

- It should not know about Stream Deck actions.
- It should not depend on Stream Deck SDK types.
- It should not parse Codex application state unless a later explicit integration is added.

Recommended implementation:

- Swift command-line helper.
- ScreenCaptureKit for the durable capture path.
- CoreGraphics only as an early probe if it speeds up window enumeration and one-shot screenshots.

The current helper follows that split: window discovery is lightweight, and any CoreGraphics snapshot is explicitly a one-shot validation path rather than the steady-state capture engine.

### `streamdeck-plugin`

Owns Stream Deck integration.

Responsibilities:

- Register one or more Stream Deck actions.
- Subscribe to or poll the latest frame.
- Call `setImage` with `data:image/png;base64,...` or a supported equivalent.
- Show placeholder images for missing permissions, missing Codex window, capture stopped, or stale frames.
- Expose user settings such as FPS, crop mode, and target display/window if needed.

Non-responsibilities:

- It should not implement macOS capture directly.
- It should not depend on Codex app internals.
- It should not perform expensive image processing per key if the capture helper can prepare the frame.

Recommended implementation:

- TypeScript / Node Stream Deck SDK plugin.
- One action for the initial MVP: `Live Pet`.
- Later actions can be added for alternate crop modes or status displays.

### `shared`

Owns the stable contract between helper and plugin.

Responsibilities:

- Frame metadata schema.
- Settings schema.
- Status/error vocabulary.
- Transport message definitions if using WebSocket.

Initial contract can be very small:

```json
{
  "version": 1,
  "framePath": "/tmp/codex-pet-streamdeck/latest.png",
  "updatedAt": "2026-05-03T12:00:00.000Z",
  "status": "ok"
}
```

## Transport

For performance, the long-term transport should be push-based. The temp directory is only the first integration step because it is easy to inspect and debug.

### MVP Transport: Temp Directory

Use a temp directory for the first useful build:

```text
/tmp/codex-pet-streamdeck/latest.png
/tmp/codex-pet-streamdeck/status.json
```

Advantages:

- Easy to inspect manually.
- Easy to build incrementally.
- Avoids WebSocket lifecycle complexity while capture behavior is still unknown.

Constraints:

- Polling introduces latency.
- Need atomic writes to avoid partial reads.
- Multiple keys or profiles may duplicate polling work.

Implementation note:

- Write frames to `latest.tmp.png`, then rename to `latest.png`.
- Write status the same way.
- Plugin should treat old `updatedAt` values as stale.

### Later Transport: Local WebSocket

Move to localhost WebSocket after capture is proven.

Advantages:

- Lower latency.
- Push-based updates.
- Cleaner support for multiple Stream Deck actions.
- Better place to expose runtime status.

Constraints:

- Need lifecycle management.
- Need port selection and retry behavior.
- Need clear behavior when helper/plugin starts first.

## Frame Model

The Stream Deck plugin should receive a ready-to-display square image.

Recommended frame output:

- `144x144` PNG for standard key mode.
- Transparent or black letterbox depending on what looks better on hardware.
- `10fps` asset-renderer default to sample Codex's shortest `110ms` avatar frames.
- `15fps` practical upper target unless hardware testing says otherwise.

The helper should prepare the final key-sized frame before the plugin sees it. The plugin should avoid per-frame crop/scale work so Stream Deck update cost stays predictable.

Modes:

- `pet`: mascot only, best first target.
- `pet-with-bubble`: mascot plus notification bubble, likely too small for a single key but useful to test.
- `debug-wide`: saved for local inspection, not sent to a single key by default.

## Process Lifecycle

Recommended initial lifecycle:

1. User starts `capture-macos` manually during development.
2. Stream Deck plugin reads frames from temp directory.
3. Plugin displays clear placeholders when the helper is absent.

Recommended later lifecycle:

1. Stream Deck plugin starts the helper when the action appears.
2. Helper keeps running while at least one action is active.
3. Helper exits after an idle timeout when no consumers remain.
4. Plugin restarts helper if it crashes.

This avoids making early permission and packaging problems block the capture work.

## Error States

Define these explicitly from the start:

- `ok`: frame is fresh.
- `codex-not-running`: no Codex process/window found.
- `window-not-found`: Codex is running but no capture target matched.
- `screen-recording-denied`: macOS capture permission missing.
- `capture-failed`: capture API returned an error.
- `stale-frame`: plugin has not seen a fresh frame in the expected interval.
- `helper-not-running`: plugin cannot find helper output.

The plugin should map each state to a simple placeholder image. That makes debugging on the hardware much less mysterious.

## Directory Layout

Recommended repository layout:

```text
capture-macos/
  Package.swift
  Sources/
    CodexPetCapture/
      main.swift
      WindowDiscovery.swift
      CaptureEngine.swift
      Cropper.swift
      FramePublisher.swift

streamdeck-plugin/
  package.json
  src/
    actions/
      LivePetAction.ts
    frame-source/
      TempFileFrameSource.ts
      WebSocketFrameSource.ts
    images/
      placeholders.ts

shared/
  protocol/
    frame-status.schema.json
  docs/
    frame-contract.md

docs/
  research.md
  architecture.md
```

## Build Order

Recommended order:

1. `capture-macos`: asset renderer mode that loads Codex-compatible pet spritesheets.
2. `capture-macos`: best-effort Codex state inference and explicit `PET_STATE` override.
3. `capture-macos`: atomic `latest-data-url.txt`, `latest.png`, and `status.json` writer.
4. `streamdeck-plugin`: data URL reader and `setImage` action.
5. `Codex Pet` menu bar app: helper lifecycle, FPS presets, config access, and fallback crop tuning.
6. `capture-overlay`: retained as an explicit fallback for pixel-level overlay mirroring.
7. Package signed helper apps and `.streamDeckPlugin` artifacts for public releases.
8. Replace temp-file polling with a push channel only if hardware testing shows it is needed.

## Architecture Verdict

The architecture is good, with one adjustment: do not let the Stream Deck plugin own rendering or capture. Make the native helper responsible for producing a finished `144x144` frame and keep the plugin as a small Stream Deck adapter.

The default helper now renders pet assets locally, which removes the riskiest capture-path concerns from normal use. The capture path remains useful as a fallback when exact rendered overlay mirroring matters.

Performance adjustment: temp-file data URL polling is acceptable for the current `144x144` renderer because writes are atomic and the plugin skips duplicate payloads. Move steady-state frame delivery to a local push channel only after measuring a real Stream Deck bottleneck.

## Initial Probe Result

The first window probe found an onscreen Codex layer `3` window with bounds `356x320`, which is likely the pet overlay. This is a good sign for performance because a small overlay window can be captured directly instead of capturing and cropping the full Codex main window.

Screen Recording permission was granted during implementation, and ScreenCaptureKit successfully captured the layer `3` overlay window directly. That proved that overlay mirroring is possible, but the default path now avoids this dependency by rendering the active Codex pet from local assets. The overlay capture path is retained as `capture-overlay` for fallback experiments.
