# Scripts

The top-level scripts are the normal local-development surface:

- `install.sh`: build the Rust renderer, install the Stream Deck plugin symlink, and write the LaunchAgent.
- `start-helper.sh` / `stop-helper.sh`: manage the asset-renderer helper.
- `status.sh`: inspect config, helper state, latest frame status, and recent errors.
- `set-fps.sh` / `set-debug.sh`: update helper config and restart manually.
- `uninstall.sh`: remove the LaunchAgent and plugin symlink.

`dev/` contains commands that are useful while hacking on this repository:

- `dev/build-apps.sh`: build the legacy Swift helper app bundles.
- `dev/open-menubar.sh`: launch the menu bar controller from the local build.
- `dev/clean-artifacts.sh`: remove ignored local frame/build artifacts.

`exact-sync/` is optional and only needed when Codex is launched with an
Electron remote debugging port:

- `exact-sync/open-codex-debug.sh`: launch Codex with `--remote-debugging-port`.
- `exact-sync/start-avatar-sync.sh` / `exact-sync/stop-avatar-sync.sh`: mirror
  Codex overlay sprite row/column and badge count into local renderer state.
- `exact-sync/sync-codex-avatar-frame.js`: implementation detail used by the
  LaunchAgent above.

`internal/` contains scripts called by LaunchAgent plists. They are not intended
as the public command surface.

Legacy capture-overlay support remains in the Swift helper and menu bar app, but
the old top-level Screen Recording and crop-preview scripts were removed to keep
the public script surface small.
