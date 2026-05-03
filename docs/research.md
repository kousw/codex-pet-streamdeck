# Codex Pet Stream Deck Research

Date: 2026-05-03

## Goal

Display the live animated Codex app pet, including its current animation state and activity bubble behavior, on an Elgato Stream Deck key.

This is not just an asset conversion problem. The desired behavior is a live mirror of what Codex draws in the bottom-right pet overlay.

## Current Findings

The practical implementation path is:

1. Capture the Codex pet overlay window or the Codex window region that contains it.
2. Crop the pet area.
3. Resize or letterbox it for the Stream Deck key canvas.
4. Send each frame to Stream Deck with `setImage`.

Animated GIF/WebP files are useful for static asset experiments, but they do not solve live mirroring because Stream Deck plugin APIs do not play animated images through `setImage`.

## Local Codex App Facts

Installed app:

- Path: `/Applications/Codex.app`
- Bundle id: `com.openai.codex`
- Version observed: `26.429.30905`
- App framework: Electron, based on `NSPrincipalClass = AtomApplication`

Installed Stream Deck app:

- Path: `/Applications/Elgato Stream Deck.app`
- Bundle id: `com.elgato.StreamDeck`
- Version observed: `7.4.0`
- Minimum macOS version in app metadata: `13.0`

Local custom pet layout:

- Directory: `$CODEX_HOME/pets/<pet-name>` or `~/.codex/pets/<pet-name>`
- Manifest: `pet.json`
- Spritesheet: `spritesheet.webp`
- Observed spritesheet size: `1536x1872`
- Derived grid: `8x9`
- Derived frame size: `192x208`

`pet.json` currently contains only metadata and `spritesheetPath`. Animation timing and row meanings are defined in the app code, not in the pet manifest.

## Codex Pet Rendering Model

The pet UI is implemented as an avatar/pet overlay, not as a simple icon file.

Observed from `/Applications/Codex.app/Contents/Resources/app.asar`:

- Overlay page asset: `webview/assets/avatar-overlay-page-Dj9Zinq_.js`
- Avatar renderer asset: `webview/assets/codex-avatar-BpKnWN_W.js`
- Avatar CSS asset: `webview/assets/codex-avatar-D82knaKt.css`
- Built-in spritesheets include:
  - `codex-spritesheet-v4-Bl6P89d_.webp`
  - `dewey-spritesheet-v4-gAYk_M9g.webp`
  - `fireball-spritesheet-v4-BtU8R9Qp.webp`
  - `rocky-spritesheet-v4-3RlTi26B.webp`
  - `seedy-spritesheet-v4-CdlE_fn9.webp`
  - `stacky-spritesheet-v4-CaUJd4fY.webp`
  - `bsod-spritesheet-v4-BRrRVy1T.webp`
  - `null-signal-spritesheet-v4-CCoTR-8t.webp`

The avatar CSS uses:

```css
.codex-avatar-root {
  aspect-ratio: 192/208;
  width: 7.04rem;
  image-rendering: pixelated;
  background-repeat: no-repeat;
  background-size: 800% 900%;
}
```

The app animates by changing CSS `background-position` over a fixed `8x9` spritesheet. The observed animation states are:

- `idle`: row 0, 6 frames, custom timing
- `running-right`: row 1, 8 frames
- `running-left`: row 2, 8 frames
- `waving`: row 3, 4 frames
- `jumping`: row 4, 5 frames
- `failed`: row 5, 8 frames
- `waiting`: row 6, 6 frames
- `running`: row 7, 6 frames
- `review`: row 8, 6 frames

The overlay maps Codex activity to mascot state approximately like this:

- Active tool/run state -> `running`
- Needs input / warning -> `waiting`
- Failed / danger -> `failed`
- Completed unread output / success -> `review`
- Otherwise -> `idle`

The overlay element exposes useful selectors in the rendered DOM:

- `.codex-avatar-root`
- `[data-avatar-mascot="true"]`
- `[data-avatar-overlay-hit-region]`
- `[data-avatar-overlay-size="notification-tray"]`

This matters if we later inspect the Electron renderer or use accessibility/browser debugging, but for a Stream Deck mirror the OS-level capture path is simpler and less coupled to app internals.

## Stream Deck Findings

Official SDK docs say `setImage` accepts either an image path or a base64 image data URL. Supported formats listed for dynamic key images are:

- SVG
- JPG/JPEG
- PNG
- WEBP

The same docs explicitly say `setImage` does not support animated image formats such as GIF. Therefore the plugin should send individual PNG or WEBP frames repeatedly.

Useful plugin facts from the official manifest docs:

- Plugins define a `CodePath`.
- Node.js plugins can declare Node version `20` or `24`.
- SDK version `3` is recommended in current docs.
- App monitoring can be declared with `ApplicationsToMonitor`, which could watch `com.openai.codex`.
- Stream Deck software 7.4 is installed locally, matching the current docs' supported range.

References:

- [Stream Deck SDK: Keys](https://docs.elgato.com/streamdeck/sdk/guides/keys/)
- [Stream Deck SDK: Manifest](https://docs.elgato.com/streamdeck/sdk/references/manifest/)
- [Stream Deck CLI: Getting Started](https://docs.elgato.com/sdk/)
- [Stream Deck CLI: create](https://docs.elgato.com/streamdeck/cli/commands/create/)

## macOS Capture Options

### Option A: ScreenCaptureKit window capture

This is the preferred direction for the capture process.

Apple positions ScreenCaptureKit as the modern framework for high-performance capture of displays, apps, and windows. It exposes concepts such as shareable content, windows, and capture streams.

Expected advantages:

- Better suited for continuous frame capture.
- Can capture a specific app/window rather than the entire display.
- More likely to keep working as older APIs are deprecated.

Expected constraints:

- Requires Screen Recording permission.
- Needs a small native macOS component, likely Swift.
- If the Codex pet overlay is its own Electron window, this can target it directly.
- If it is only part of a larger window, we still need to crop the bottom-right region.

Reference:

- [Apple Developer: ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)

### Option B: CoreGraphics window screenshot

`CGWindowListCreateImage` historically allowed window snapshots, but Apple marks it deprecated. This can still be useful for a quick prototype, but it should not be the long-term core if ScreenCaptureKit works.

Expected advantages:

- Simpler one-shot screenshot prototype.
- Useful for quickly proving window discovery and cropping.

Expected constraints:

- Deprecated API.
- May behave poorly with offscreen, hidden, or occluded windows depending on OS behavior and permissions.
- Not ideal for smooth live frame streaming.

Reference:

- [Apple Developer: CGWindowListCreateImage](https://developer.apple.com/documentation/coregraphics/cgwindowlistcreateimage%28_%3A_%3A_%3A_%3A%29)

### Option C: Whole-screen capture and crop

This is the fallback path if window targeting is annoying.

Expected advantages:

- Simple.
- Good enough for an MVP when Codex is visible.

Expected constraints:

- Breaks if the window moves, is hidden, or another window covers the pet.
- Needs user-configurable crop coordinates.
- Captures more screen content than necessary.

## Proposed Architecture

```text
capture-macos/
  Swift process
  Finds Codex windows for bundle id com.openai.codex
  Captures the overlay/window or a configured crop
  Emits latest frame as PNG or raw BGRA

streamdeck-plugin/
  TypeScript/Node Stream Deck plugin
  Receives latest frame
  Calls setImage(data:image/png;base64,...)

shared/
  Frame transport protocol
  Settings schema
```

Recommended local transport:

- MVP: capture process writes latest frame to a temp file, plugin polls it.
- Better: capture process exposes a localhost WebSocket, plugin subscribes.
- Later: plugin launches and supervises capture process.

For the first proof of life, a temp file is less elegant but easier to debug:

```text
/tmp/codex-pet-streamdeck/latest.png
```

The plugin can start by polling at `5-10fps`. That is enough for a small Stream Deck key and avoids hammering the Stream Deck app.

## Crop and Canvas Strategy

Stream Deck keys are typically designed around square images. The SDK dynamic image accepts formats rather than requiring a fixed size, but `144x144` is the conventional target size for key artwork.

The Codex pet itself is `192x208`, not square. The overlay plus bubble can be wider than a single key.

Recommended modes:

- `pet`: crop only the mascot and fit to `144x144`.
- `pet-with-bubble`: crop mascot plus notification bubble, fit into `144x144` with letterboxing.
- `wide-debug`: save the full cropped overlay for local inspection, not for a single key.

For a single physical key, `pet` will probably look best. `pet-with-bubble` may be legible only when the bubble is short.

## MVP Plan

1. Create `capture-macos` prototype using Swift.
2. Enumerate windows for `com.openai.codex`.
3. Print window ids, names, bounds, and layer/order.
4. Capture one frame from the best candidate window.
5. Crop the observed mascot region and write `latest.png`.
6. Loop at low FPS and confirm the PNG changes while the pet animates.
7. Scaffold Stream Deck plugin with the official CLI.
8. Implement one action that polls `latest.png` and calls `setImage`.
9. Add settings for crop mode, FPS, and target window selection.

## Main Risks

- The pet overlay may be a transparent, always-on-top Electron child/utility window, or it may be part of a larger Codex window. The capture strategy changes slightly depending on what macOS exposes.
- Screen Recording permission is mandatory for reliable capture. The capture binary must be the thing macOS grants permission to.
- If the capture process is launched by Stream Deck, permission prompts may refer to Stream Deck or the helper binary depending on packaging.
- A single key may be too small for the speech bubble. Mirroring the mascot alone is likely to feel better.
- Sending frames too frequently may be wasteful. Start around `8fps`, then tune.
- The Codex app internals are not a public API. DOM selectors and bundle filenames may change. OS-level capture is less brittle than injecting into the app.

## Open Questions

- Does macOS expose the pet overlay as its own window, or only as part of the main Codex window? Initial probe suggests there is an independent layer `3` Codex window that matches the pet overlay.
- What are the real bounds of the overlay window on this machine? Initial probe found an onscreen layer `3` Codex window at `356x320`.
- Can ScreenCaptureKit capture the Codex overlay when the main app is not focused? It can capture the overlay while visible; focus/occlusion behavior still needs testing.
- Does capture continue when another window overlaps Codex?
- What FPS feels good on the actual Stream Deck hardware?
- Should the plugin show a placeholder when Codex is closed, hidden, or permission is missing?

## Recommendation

Use ScreenCaptureKit for the real implementation, but begin with a tiny native capture probe that only lists Codex windows and writes one cropped PNG. Once that proves the window model, wire it to a Stream Deck plugin through a simple temp-file frame handoff.

This keeps the first milestone small while still pointing at the architecture we would actually want to keep.
