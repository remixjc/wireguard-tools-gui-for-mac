# WireGuard Tray

A lightweight macOS menu-bar app for managing [wireguard-tools](https://formulae.brew.sh/formula/wireguard-tools)
(`wg` / `wg-quick`) installed via Homebrew.

Unlike the App Store WireGuard client, it fully supports the `PostUp` / `PostDown`
hooks in your config files — and gives them a UI.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-brightgreen)

## Features

- **Status bar indicator** — green / gray dot showing tunnel connected / disconnected, refreshed every 2 s.
- **One-click start / stop** — runs `wg-quick up <name>` / `wg-quick down <name>` with a
  one-time passwordless sudo whitelist (AppleScript admin prompt as fallback).
- **Tunnel list** — scans `/etc/wireguard/*.conf`, switch & start any config from the menu.
- **Config detail window** — view parsed `[Interface]` / `[Peer]` fields and `PostUp` / `PostDown` lines.
- **Interface picker for PostUp/PostDown** — macOS tunnel interfaces (`utunN`) are numbered
  dynamically and change across reboots, breaking rules that hard-code `dev utun8`.
  The app enumerates system interfaces (`networksetup` + `ifconfig`) into a dropdown,
  replaces the `dev <iface>` reference, backs up the original file (`*.conf.bak-<timestamp>`)
  and writes back atomically.
- **Launch at login** (macOS 13+, `SMAppService`).
- **Bilingual UI** — 简体中文 / English.

## Requirements

- macOS 13+
- [Homebrew](https://brew.sh)
- `brew install wireguard-tools`
- One or more configs in `/etc/wireguard/<name>.conf` (created with `sudo`)

## Build

```bash
./Scripts/build-app.sh
# => dist/WireGuardTray.app
```

The app uses a pure AppKit status-bar implementation with no third-party dependencies
(SwiftPM only). CI builds and tests on every push (see `.github/workflows/build.yml`).

## Install

1. Build or download the release, then copy `WireGuardTray.app` into `Applications`.
2. (Recommended) install the one-time passwordless privilege whitelist:

   ```bash
   sudo ./Scripts/install-sudoers.sh
   ```

   This writes a whitelist at `/etc/sudoers.d/wireguard-tray` that allows **only**
   `wg-quick up <name>` and `wg-quick down <name>` for admin users — no arbitrary commands.
   Without it, the app falls back to a system admin-prompt dialog on each start/stop.

   You can also copy the same command from **Settings → Privilege** inside the app.

3. Launch the app. A green/gray dot appears in the menu bar.

## Usage

- Click the menu-bar dot to open the menu: status, start/stop, tunnel list, settings, config detail.
- **Config Detail** → pick an interface in the dropdown → **Apply Selected Interface**:
  every `dev <iface>` reference in `PostUp` / `PostDown` is replaced, the original file is
  backed up, and the new config is written atomically.

## Security notes

- The sudoers rule pins the absolute `wg-quick` path (prevents PATH hijacking) and whitelists
  only `up` / `down` on config names.
- Config writes are atomic (temp file + rename) and always preceded by a timestamped backup.
- The app is ad-hoc signed when built locally; distribute via GitHub Releases and let
  contributors with an Apple Developer account sign it with Developer ID if needed.

## FAQ

**Q: Why not just use the App Store WireGuard app?**  
A: The official app does not run your `PostUp` / `PostDown` scripts; `wg-quick` does.
This tool is a UI for exactly that workflow.

**Q: `wg-quick up` needs root — is it safe?**  
A: Yes. The privilege rule is scoped to two fixed commands via `sudoers.d`, and the UI never
runs arbitrary commands.

## License

MIT — see [LICENSE](LICENSE).
