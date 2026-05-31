# Security Review

This is a pre-publication checklist for the local preview.

## Checked

- No API keys, tokens, passwords, or Authorization headers are present in the repository text.
- Local runtime frames are generated under the Stream Deck plugin `frames/` directory and are ignored by `.gitignore`.
- Build output under `dist/`, SwiftPM `.build/`, and Rust `target/` directories are ignored.
- The FPS/config file lives under `~/Library/Application Support/Codex Pet StreamDeck/config.env`, not in the repository.
- The default asset renderer reads local Codex pet spritesheets and local Codex session state only; it does not capture the screen, upload frames, or use network transport.
- The optional exact-sync bridge connects only to the local Codex Electron DevTools endpoint on `127.0.0.1` and writes sprite row/column plus notification badge count to `~/.codex/pet-streamdeck-state.json`.
- The capture fallback only captures the Codex app overlay/window selected by bundle id `com.openai.codex`; it does not upload frames or use network transport.
- The Stream Deck plugin reads local frame files and sends image data only to the local Stream Deck websocket provided by the Stream Deck app.

## Notes

- Generated frame images can contain rendered custom pet artwork, and the capture fallback can contain a live capture of the Codex pet overlay. They should be treated as local runtime artifacts and not committed.
- `status.json` can contain local absolute paths and window ids. It is ignored.
- `~/.codex/pet-streamdeck-state.json` is local runtime state. It can contain the selected pet id, live sprite row/column, and notification badge count. It is not part of the repository.
- `dist/*.app` bundles are ignored because they are machine-built artifacts and may carry local signing metadata or extended attributes.
- Screen Recording permission is not required for the default Rust asset renderer. Users should grant it only to the generated `Codex Pet Capture` app when explicitly using the `capture-overlay` fallback.
- Electron remote debugging is optional and should be treated as a developer feature. Users must launch Codex with the debug port intentionally; the project does not expose the port itself.

## Before Publishing

- Re-run a text scan for local paths and credentials.
- Package signed/notarized release artifacts separately from source.
- Keep generated `frames/`, `dist/`, logs, and local config out of source control.
- Run `./scripts/dev/clean-artifacts.sh` before creating a source archive if local runtime frames were generated.
