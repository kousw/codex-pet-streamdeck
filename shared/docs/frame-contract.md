# Frame Contract

The helper and Stream Deck plugin communicate through a narrow frame/status
contract. The helper may be either the original capture publisher or the planned
asset renderer.

## Performance Direction

The durable architecture should prefer a push-based local stream after the capture path is proven. The temp-file contract exists for the first integration milestone because it is inspectable and easy to debug, not because polling PNG files is the long-term performance target.

Recommended stages:

1. Window probe only.
2. One-shot frame write.
3. Low-FPS temp-file frame publishing for Stream Deck proof of life.
4. Local WebSocket or equivalent push transport for steady-state use.

## Temp Directory Contract

Installed local directory:

```text
~/Library/Application Support/com.elgato.StreamDeck/Plugins/com.kousw.codex-pet.sdPlugin/frames
```

Files:

```text
latest.png
latest-data-url.txt
frame-0.png
frame-1.png
...
frame-7.png
status.json
```

Writers must use atomic replacement:

1. Write to a temporary path in the same directory.
2. Flush and close the file.
3. Rename into place.

Readers should treat frames as stale when `updatedAt` is older than the expected frame interval plus tolerance.

The publisher rotates through `frame-0.png` to `frame-7.png` for consumers that need changing file paths. The current Stream Deck plugin reads `latest-data-url.txt` instead, because `setImage` accepts a data URL and avoids file path caching behavior.

`status.json` includes:

- `captureFPS`: the helper's configured frame rate. The plugin uses this to derive its polling interval.
- `crop`: the configured pet crop rectangle in reference overlay coordinates.

The asset-renderer path should also write `renderFPS`, `source`, `stateSource`,
`petId`, `petState`, and optionally `notificationBadgeCount`. During migration
it should keep writing `captureFPS` for compatibility with the current plugin.

## Status Values

- `ok`: frame is fresh.
- `codex-not-running`: no Codex process/window found.
- `window-not-found`: Codex is running but no capture target matched.
- `screen-recording-denied`: macOS capture permission missing.
- `capture-failed`: capture API returned an error.
- `stale-frame`: plugin has not seen a fresh frame in the expected interval.
- `helper-not-running`: plugin cannot find helper output.
