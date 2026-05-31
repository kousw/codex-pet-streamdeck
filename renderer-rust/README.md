# Codex Pet Renderer

Experimental Rust renderer daemon for Codex-compatible pet spritesheets.

This is the candidate cross-platform replacement for the current Swift
asset-renderer helper. It keeps the existing Stream Deck frame contract so the
Stream Deck plugin can remain a small display adapter.

## Run

```sh
cargo run -- \
  --fps 10 \
  --duration 3 \
  --output-dir ../streamdeck-plugin/com.kousw.codex-pet.sdPlugin/frames
```

The renderer writes:

- `latest.png`
- `latest-data-url.txt`
- `status.json`
- rotating `frame-0.png` ... `frame-7.png`

It can also expose a small local HTTP API:

```sh
cargo run -- \
  --output-dir ../streamdeck-plugin/com.kousw.codex-pet.sdPlugin/frames \
  --http 127.0.0.1:47847
```

Endpoints:

- `GET /health`
- `GET /status`
- `GET /frame/latest.png`
- `GET /frame/latest-data-url`

## Scope

Implemented:

- custom pet discovery from `CODEX_HOME` or `~/.codex/pets`
- `pet.json` + `spritesheet.webp`
- Codex `8 x 9` timeline-compatible sprite animation
- existing file-based Stream Deck frame contract
- optional HTTP read API

Not implemented yet:

- Codex activity inference
- exact Electron debug-port sync
- install/start/status packaging
- Windows startup integration
