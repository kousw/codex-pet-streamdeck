# Asset Renderer Migration Plan

Date: 2026-05-31

## Summary

The original prototype mirrored the rendered Codex pet overlay by capturing a
macOS window, cropping it, and publishing Stream Deck-ready PNG frames.

That approach proved the concept, but it carries avoidable operational cost:

- macOS Screen Recording permission is required.
- Crop settings are fragile because the overlay layout can move.
- Frame files can be read while they are being replaced unless every writer path is careful.
- The helper depends on rendered UI instead of the pet data model.
- The steady-state loop is limited by capture cost rather than the pet animation model.

The default architecture should move to an asset renderer:

```text
Codex local state + pet spritesheet
  -> local pet state bridge
  -> native frame renderer
  -> latest-data-url.txt/status.json
  -> Stream Deck plugin setImage
```

The Stream Deck plugin can continue consuming `latest-data-url.txt`. The main
change is replacing "capture pixels from the Codex overlay" with "render the same
pet frame locally from Codex pet assets and inferred Codex activity state."

## Reference Implementation

This design is informed by
[lkuczborski/WatchPet](https://github.com/lkuczborski/WatchPet), an Apple Watch
companion for the Codex pet overlay.

WatchPet uses a better architecture for watchOS than live image mirroring:

- A local Node bridge serves state and pet assets.
- The watch app renders the pet from Codex spritesheets.
- The bridge reads built-in Codex app spritesheets and custom pets from
  `~/.codex/pets`.
- It can use Codex's Electron remote debugging port for a more live overlay
  state when Codex is launched with remote debugging enabled.
- It falls back to local Codex session JSONL data when live overlay state is not
  available.

We should borrow the architecture, not necessarily the exact implementation.
For Stream Deck, the display endpoint is still `setImage`, so our helper should
render frames into data URLs rather than making the plugin implement a full pet
renderer.

## Why This Is Better

The asset renderer avoids the most painful parts of the capture prototype.

Benefits:

- No Screen Recording permission for the default path.
- No crop tuner required for normal pet rendering.
- No dependency on the pet overlay window being visible, positioned, or
  capturable.
- Better animation quality because frames come directly from the spritesheet.
- Lower CPU and GPU cost than repeated window capture.
- More stable behavior when Codex is hidden, covered, or moved.
- Easier support for custom pets because Codex pet packages already provide
  `pet.json` and `spritesheet.webp`.

Tradeoffs:

- It is not a pixel-perfect mirror of the Codex overlay.
- Bubble layout and exact overlay text must be reconstructed from state.
- Codex does not currently expose a stable public pet state API.
- Reading Electron remote debugging or session JSONL is still an internal
  integration and can change.

## Target Architecture

### `codex-pet-renderer`

This can initially live in `capture-macos` as a new mode or product, but it
should be conceptually separate from capture.

Responsibilities:

- Resolve the selected pet.
- Load a built-in or custom spritesheet.
- Infer the current Codex activity state.
- Map activity state to a pet animation row.
- Sample the Codex avatar animation timeline at the configured FPS.
- Render a `144x144` PNG data URL.
- Write `latest-data-url.txt` and `status.json` using the existing atomic file
  contract.

Non-responsibilities:

- It should not capture the screen.
- It should not crop the Codex overlay.
- It should not depend on Stream Deck SDK APIs.

### `streamdeck-plugin`

The plugin should remain a thin Stream Deck adapter.

Responsibilities:

- Poll `latest-data-url.txt`.
- Call `setImage`.
- Read `status.json` for refresh timing and errors.
- Open Codex on key press where possible.

No major plugin rewrite is required for the first migration. The current data
URL contract is already the right shape.

### `capture-macos`

The existing capture path should be retained as a fallback while the renderer is
validated.

New mode names should make the distinction explicit:

- `render-assets`: default future mode, no Screen Recording permission.
- `capture-overlay`: current fallback mode, uses CoreGraphics/ScreenCaptureKit.

## State Sources

Use layered state discovery so the renderer degrades gracefully.

### 1. Explicit Override

Read an optional local JSON file first:

```text
~/.codex/pet-streamdeck-state.json
```

Example:

```json
{
  "petId": "custom:emilia",
  "state": "running",
  "notificationBadgeCount": 1,
  "message": "Running command",
  "pollAfterMs": 1000
}
```

This gives us a stable test seam and a possible future integration point if
Codex exposes a state file.

### 2. Codex Persisted State

Read Codex's persisted app state to resolve selected or recently awakened pets
when possible.

Expected useful keys include avatar/pet-related persisted atom state. This must
be treated as best-effort because it is not a public API.

### 3. Custom Pet Directory

Discover custom pets from:

```text
~/.codex/pets/<pet-id>/pet.json
~/.codex/pets/<pet-id>/spritesheet.webp
```

The current custom pet manifest is small and usually contains:

```json
{
  "id": "example",
  "displayName": "Example",
  "description": "A Codex-compatible animated pet.",
  "spritesheetPath": "spritesheet.webp"
}
```

### 4. Codex Built-in Assets

For built-in pets, copy or extract spritesheets from the installed Codex app
bundle. Asset filenames are versioned build artifacts, so they are less stable
than custom pet folders.

The renderer should prefer custom pets and use built-ins as a fallback.

### 5. Codex Session JSONL

Infer activity from the most recent local Codex session when no live state is
available.

Approximate mapping:

```text
task/tool running        -> running
waiting for user input   -> waiting
failed/error             -> failed
completed with output    -> review
otherwise                -> idle
```

This is not exact overlay state, but it is enough for a Stream Deck status pet.

### 6. Electron Remote Debugging

Optionally support the WatchPet-style live path:

```sh
/Applications/Codex.app/Contents/MacOS/Codex --remote-debugging-port=9222
```

If available, the helper can query the live renderer state from Codex. This
should remain optional because requiring users to relaunch Codex with a debug
port is too much setup for the default path.

## Rendering Model

Codex pets use an `8 x 9` spritesheet.

Observed frame layout:

- Sheet size: `1536 x 1872`
- Frame size: `192 x 208`
- Columns: `8`
- Rows: `9`

Observed rows:

| Row | State |
| --- | --- |
| 0 | idle |
| 1 | running-right |
| 2 | running-left |
| 3 | waving |
| 4 | jumping |
| 5 | failed |
| 6 | waiting |
| 7 | running |
| 8 | review |

First implementation can use fixed frame counts:

| State | Row | Frames |
| --- | ---: | ---: |
| idle | 0 | 6 |
| running | 7 | 6 |
| waiting | 6 | 6 |
| failed | 5 | 8 |
| review | 8 | 6 |

The renderer should crop one frame from the spritesheet and draw it into a
`144x144` Stream Deck canvas with nearest-neighbor scaling and black or
transparent padding.

Codex's current avatar renderer does not use a uniform frame interval:

- idle frames use `280, 110, 110, 140, 140, 320ms`, multiplied by `6`
  for the slow idle loop.
- `running`, `waiting`, `failed`, and `review` play their state row three times
  with their own per-frame durations, then return to the slow idle loop while
  the state remains unchanged.
- The Stream Deck helper should therefore choose frames by elapsed wall-clock
  time since the pet/state changed, not by `sequence % frameCount`.

`10fps` is the practical renderer default because the shortest Codex avatar
frame is `110ms`. Lower values are valid but may skip short frames.

## Output Contract

Keep the existing plugin contract:

```text
frames/latest-data-url.txt
frames/status.json
```

`latest-data-url.txt`:

```text
data:image/png;base64,...
```

`status.json` should gain source fields:

```json
{
  "version": 2,
  "status": "ok",
  "source": "asset-renderer",
  "stateSource": "codex-session",
  "petId": "custom:emilia",
  "petState": "running",
  "renderFPS": 5,
  "updatedAt": "2026-05-31T00:00:00Z"
}
```

The plugin currently reads `captureFPS`; during migration, write both
`captureFPS` and `renderFPS` for compatibility.

## Migration Steps

1. Add an asset-renderer service mode that writes the existing frame contract.
2. Render a fixed custom pet and fixed state from a spritesheet.
3. Add state cycling for local visual testing.
4. Resolve custom pets from `~/.codex/pets`.
5. Infer state from local session JSONL.
6. Resolve selected pet from persisted Codex state on a best-effort basis.
7. Update scripts so the default helper mode is asset rendering.
8. Keep capture mode as an explicit fallback and update docs accordingly.
9. Remove Screen Recording setup from the default README path.
10. Revisit Stream Deck refresh limits after the renderer is stable.

## Open Questions

- Which persisted Codex key should be treated as the selected pet source?
- The debug-overlay bridge can add `notificationBadgeCount` so the renderer
  draws the same small activity badge as the Codex overlay.
- Should the helper be Swift-only, Node-only, or split into a Node state bridge
  plus Swift renderer?
- Do we need built-in pet extraction for the first release, or is custom pet
  support enough?
- How much live overlay exactness is worth the complexity of Electron remote
  debugging?

## Recommended Implementation Shape

The asset-renderer helper can reasonably be either Swift or Node because it runs
as a normal background process. The best split depends on which part of the
problem we optimize for.

Node advantages:

- Easier JSON/session parsing.
- Easier Electron remote-debugging integration.
- Easier reuse of WatchPet-style bridge patterns.
- Closer to the Stream Deck plugin runtime and web asset model.

Swift advantages:

- Built-in ImageIO support for WebP decode and PNG encode.
- No npm/native image dependency such as `sharp` or `canvas`.
- Existing app bundle, LaunchAgent, menu bar, and atomic file writer already
  work.
- Better fit for keeping the capture fallback in the same binary.

Recommended near-term shape:

```text
Swift helper
  - renders spritesheets to 144x144 PNG data URLs
  - keeps capture-overlay fallback
  - keeps LaunchAgent/app bundle/menu bar integration

Optional Node bridge later
  - resolves richer Codex live/session state
  - queries Electron remote debugging when enabled
  - writes a small state file consumed by the Swift renderer
```

If we decide to add a bundled Node dependency such as `sharp`, a pure Node
renderer is also viable. Until then, Swift is the lower-dependency renderer and
Node is better treated as a possible state bridge.

The initial Swift renderer can stay small:

```text
AssetPetService
  PetResolver
  CodexStateResolver
  SpriteSheetRenderer
  DataURLPublisher
```

The old capture helper remains available for `capture-overlay` mode. Once the
asset renderer works on hardware, rename the project language from "capture" to
"render" in public docs.
