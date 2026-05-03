# Security Review

This is a pre-publication checklist for the local preview.

## Checked

- No API keys, tokens, passwords, or Authorization headers are present in the repository text.
- Local runtime frames are generated under the Stream Deck plugin `frames/` directory and are ignored by `.gitignore`.
- Build output under `dist/` and SwiftPM `.build/` directories are ignored.
- The FPS/config file lives under `~/Library/Application Support/Codex Pet StreamDeck/config.env`, not in the repository.
- The capture helper only captures the Codex app overlay/window selected by bundle id `com.openai.codex`; it does not upload frames or use network transport.
- The Stream Deck plugin reads local frame files and sends image data only to the local Stream Deck websocket provided by the Stream Deck app.

## Notes

- Generated frame images can contain a live capture of the Codex pet overlay. They should be treated as local runtime artifacts and not committed.
- `status.json` can contain local absolute paths and window ids. It is ignored.
- `dist/*.app` bundles are ignored because they are machine-built artifacts and may carry local signing metadata or extended attributes.
- Screen Recording permission is required. Users should grant it only to the generated `Codex Pet Capture` app.

## Before Publishing

- Re-run a text scan for local paths and credentials.
- Package signed/notarized release artifacts separately from source.
- Keep generated `frames/`, `dist/`, logs, and local config out of source control.
- Run `./scripts/clean-artifacts.sh` before creating a source archive if local runtime frames were generated.
