# Stream Deck Plugin

Minimal Stream Deck plugin for displaying the frame written by the macOS capture helper.

The plugin consumes `com.kousw.codex-pet.sdPlugin/frames/latest-data-url.txt`. It does not perform macOS capture directly.

Initial action:

- `Live Pet`: displays the latest prepared `144x144` frame.

Performance target:

- Start with conservative update rates. The plugin reads `frames/status.json`, derives its polling interval from `captureFPS`, and uses a Web Worker timer with a main-thread timer fallback.
- Avoid repeated expensive image transforms in the plugin.
- Move from temp-file polling to push transport once capture behavior is proven.

## Install Locally

The recommended path is the repository-level installer:

```sh
../scripts/install.sh
```

It builds the macOS helper apps, installs the LaunchAgent, and symlinks `com.kousw.codex-pet.sdPlugin` into:

```text
~/Library/Application Support/com.elgato.StreamDeck/Plugins/
```

Then restart Stream Deck. If you only want to work on the plugin, copying or symlinking `com.kousw.codex-pet.sdPlugin` into that folder is also enough, but the key will not show live frames until the capture helper is running.

## Try It

Start the capture helper:

```sh
cd ../capture-macos
swift run codex-pet-capture --serve --frame-mode pet --capture-engine core-graphics --fps 1 --output-dir ../streamdeck-plugin/com.kousw.codex-pet.sdPlugin/frames
```

In Stream Deck, add the `Codex -> Live Pet` action to a key.

If the key does not change, make sure the action does not have a user-customized icon. Stream Deck only allows plugin `setImage` updates when the user has not specified a custom image for that key.

Pressing the key requests `codex://` via Stream Deck `openUrl`, which should launch or foreground Codex if the app has registered the URL scheme.

## Runtime Notes

The plugin reads `frames/latest-data-url.txt` with `XMLHttpRequest`, then sends that data URL to Stream Deck with `setImage`. It also polls `frames/status.json` once per second and adjusts the frame read interval to roughly `1000 / captureFPS` milliseconds, clamped to `67...1000ms`.

`fetch()` was avoided because the Stream Deck plugin runtime failed local file reads in testing. The refresh loop uses a Web Worker timer because normal HTML timers may be throttled or paused by the Stream Deck runtime.

The plugin skips duplicate image payloads per key, so raising capture FPS does not repeatedly send identical frames. The conservative public default is still `1fps`; `5fps` is a reasonable local test value, and `8fps` is closer to the Codex pet's faster running animations.
