# WireGuard Tray

> A lightweight macOS menu-bar app for managing [wireguard-tools](https://formulae.brew.sh/formula/wireguard-tools)
> (`wg` / `wg-quick`) installed via Homebrew, with a GUI for status, one-click
> start/stop, config inspection, and PostUp/PostDown interface editing.

Unlike the App Store WireGuard client, **this tool fully supports the `PostUp` / `PostDown`
hooks** in your config files — the `wg-quick` capability (e.g. setting up a SOCKS proxy or
routing rules on connect) that the official app never runs.

**English** | [中文](README.md)

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-brightgreen)

---

## Table of Contents

- [Features](#features)
- [Prerequisites (read first)](#prerequisites-read-first)
  - [1. Install Homebrew](#1-install-homebrew)
  - [2. Install wireguard-tools](#2-install-wireguard-tools)
  - [3. Create a WireGuard config](#3-create-a-wireguard-config)
  - [4. Verify the tunnel works in the terminal](#4-verify-the-tunnel-works-in-the-terminal)
- [Install WireGuard Tray](#install-wireguard-tray)
  - [Option A: Build it](#option-a-build-it)
  - [Option B: Download a release](#option-b-download-a-release)
  - [Configure passwordless privilege (recommended)](#configure-passwordless-privilege-recommended)
- [Usage Guide](#usage-guide)
  - [Menu bar](#menu-bar)
  - [Config detail window](#config-detail-window)
  - [Interface editing (PostUp/PostDown)](#interface-editing-postuppostdown)
  - [Settings](#settings)
- [How connection status is detected](#how-connection-status-is-detected)
- [Project structure & development](#project-structure--development)
- [Security notes](#security-notes)
- [FAQ](#faq)
- [License](#license)

---

## Features

- **Status bar indicator** — green / gray dot showing tunnel connected / disconnected,
  refreshed every 2 s.
- **One-click start / stop** — runs `wg-quick up <name>` / `wg-quick down <name>` and fully
  executes PostUp / PostDown; uses a one-time passwordless sudo whitelist by default,
  with a system admin-prompt fallback.
- **Tunnel list** — scans all of wg-quick's config search paths; switch and start any config
  from the menu.
- **Config detail window** — view parsed `[Interface]` / `[Peer]` fields and `PostUp` / `PostDown` lines.
- **Interface editor** — supports both reference styles:
  - `dev <iface>` device-name style (e.g. `ip route add default dev utun8 ...`)
  - `networksetup` network-service style (e.g. `networksetup -setsocksfirewallproxy "Ethernet" 127.0.0.1 7890`)

  Enumerates system interfaces live (`networksetup` + `ifconfig`) into a dropdown, replaces the
  reference in the config, backs up the original file (`*.conf.bak-<timestamp>`), and writes
  back atomically.
- **Launch at login** (macOS 13+, `SMAppService`).
- **Bilingual UI** — 简体中文 / English.

## Prerequisites (read first)

Do these steps in the terminal **before** using the GUI, to make sure the tunnel itself works.

### 1. Install Homebrew

On macOS use [Homebrew](https://brew.sh) (official installer; requires Xcode command line tools):

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Verify:

```bash
brew --version
```

### 2. Install wireguard-tools

```bash
brew install wireguard-tools
```

Verify the executables exist (Apple Silicon prefix is `/opt/homebrew`, Intel is `/usr/local`):

```bash
which wg wg-quick
# Expected on Apple Silicon:
#   /opt/homebrew/bin/wg
#   /opt/homebrew/bin/wg-quick
```

> If you get `command not found`, run `brew doctor` and make sure `/opt/homebrew/bin` is on your `PATH`.

### 3. Create a WireGuard config

`wg-quick` searches configs in this order (matches the script's built-in `CONFIG_SEARCH_PATHS`):

```
/etc/wireguard                 ← system default
/usr/local/etc/wireguard       ← Intel Homebrew
/opt/homebrew/etc/wireguard    ← Apple Silicon Homebrew (this app scans all of them)
```

Create the config directory (the Homebrew one is convenient — no root needed to write):

```bash
mkdir -p /opt/homebrew/etc/wireguard
```

With config name `fire`, create `/opt/homebrew/etc/wireguard/fire.conf`:

```ini
[Interface]
PrivateKey = <your private key>
Address = 10.8.0.7/24
DNS = 223.5.5.5,1.1.1.1
# On connect: point the macOS network service "Ethernet" SOCKS proxy at local port 7890
PostUp = networksetup -setsocksfirewallproxy "Ethernet" 127.0.0.1 7890
# On disconnect: turn that SOCKS proxy off
PostDown = networksetup -setsocksfirewallproxystate "Ethernet" off

[Peer]
PublicKey = <peer public key>
PresharedKey = <pre-shared key, optional>
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
Endpoint = <server address>:51820
```

> **Two interface reference styles in PostUp/PostDown**:
> - `dev <iface>` references a **device interface name** (e.g. `utun8`, `en0`). On macOS the
>   WireGuard tunnel interface number (`utunN`) is assigned dynamically and can change across
>   reboots, breaking hard-coded rules — this is exactly the pain point the editor fixes.
> - `networksetup ... "service"` references a **network service name** (e.g. `Ethernet`, `Wi-Fi`),
>   which can be replaced from the same dropdown.

### 4. Verify the tunnel works in the terminal

Make sure the tunnel starts and stops cleanly before using the GUI:

```bash
# Start
sudo wg-quick up fire
# List interfaces (on macOS the interface is usually utunN, NOT fire — that is normal)
wg show interfaces
# Stop (fully runs PostDown)
sudo wg-quick down fire
```

## Install WireGuard Tray

### Option A: Build it

Requires Xcode (or Xcode command line tools + Swift):

```bash
git clone git@github.com:remixjc/wireguard-tools-gui-for-mac.git
cd wireguard-tools-gui-for-mac
./Scripts/build-app.sh
# => dist/WireGuardTray.app
```

### Option B: Download a release

Download the packaged `WireGuardTray-0.1.0.zip`, unzip and drag `WireGuardTray.app`
into `Applications`. If Gatekeeper warns on first launch (local ad-hoc signature),
right-click → Open.

### Configure passwordless privilege (recommended)

Start/stop needs root. Two ways to configure it:

**Inside the app (recommended)**: open **Settings → Privilege**, click the **Install** button,
enter your admin password once; the whitelist is written and verified automatically.

**Command line script**:

```bash
sudo ./Scripts/install-sudoers.sh
```

The script writes a whitelist at `/etc/sudoers.d/wireguard-tray` that allows **only**:

```
%admin ALL=(root) NOPASSWD: /opt/homebrew/bin/wg-quick up *, /opt/homebrew/bin/wg-quick down *
```

- Pins the absolute `wg-quick` path (prevents PATH hijacking)
- Allows only the `up` / `down` subcommands — no arbitrary commands
- Without it, the app shows a system admin-prompt dialog on every start/stop (functionality is
  unaffected, just one extra confirmation)

Launch the app; a green/gray dot appears in the menu bar.

## Usage Guide

### Menu bar

Click the status-bar dot to open the menu:

- **Status**: Connected (green) / Disconnected (gray)
- **Start / Stop**: runs `wg-quick up` / `wg-quick down` for the selected config
- **Tunnel list**: switch the active config (scans all search paths; same-name configs are
  de-duplicated by path priority)
- **Config Detail**: open the detail window
- **Settings**: language, launch at login, privilege
- **Open Config Folder**: reveal the first existing config directory in Finder
- **Quit**

> If the tunnel was started externally (e.g. from a terminal), the menu shows the external
> tunnel status; Stop still works (`wg-quick down` when the config is in a search path,
> otherwise an interface-destroy fallback).

### Config detail window

- Top: config name and live status (**Running** green / **Stopped** gray; refreshes with the
  status poll)
- Middle: interface picker and **Apply Selected Interface** button
- Bottom: the full parsed config content (read-only)

### Interface editing (PostUp/PostDown)

1. Open **Config Detail**.
2. Pick a system interface from the dropdown (shown as `Service · Device`, e.g. `Ethernet · en0`).
3. Click **Apply Selected Interface**.

Replacement is automatic based on the reference style:

| Reference in config | Replaced with |
| --- | --- |
| `dev <iface>` (e.g. `dev utun8`) | the picked device name (e.g. `en0`) |
| `networksetup ... "service"` (e.g. `"Ethernet"`) | the picked service name (e.g. `Ethernet`) |

- A timestamped backup is created first: `fire.conf.bak-20260929-153000`
- The write-back is atomic (temp file + replace)
- Mixed references on the same line are handled correctly

### Settings

- **Language**: 简体中文 / English, switches instantly
- **Launch at Login**: auto-start on login (macOS 13+)
- **Privilege**: shows the passwordless status; click **Install** when not configured

## How connection status is detected

On macOS `wg-quick` creates a system-assigned interface (`utunN`), so **interface name ≠ config
name**. The app detects connection as follows:

1. The selected config name is itself an active interface (standard Linux case)
2. The interface recorded by wg-quick (`/var/run/wireguard/<name>.name`) is active
3. Fallback: any WireGuard tunnel is running on the system (externally started tunnels are detected too)

## Project structure & development

```
Sources/
  WireGuardCore/  pure, unit-testable logic: config parsing, command execution, interface
                  enumeration, PostUp editing
  WireGuardTray/  pure AppKit UI: status bar, menu, detail window, settings window, L10n
Tests/
  WireGuardCoreTests/  23 unit tests
Scripts/
  build-app.sh          build & package the .app (incl. ad-hoc signing)
  install-sudoers.sh   install the one-time passwordless sudoers rule
  uninstall.sh         remove the sudoers rule
.github/workflows/build.yml  CI: build + test + package on every push
```

Build & test:

```bash
swift build -c release          # compile
swift test                      # run all tests
./Scripts/build-app.sh          # produce dist/WireGuardTray.app
```

## Security notes

- The sudoers rule pins the absolute `wg-quick` path and allows only `up` / `down` — no
  arbitrary commands
- Config writes are atomic and always preceded by a backup
- Locally built binaries are ad-hoc signed; re-sign with a Developer ID before public
  distribution
- The app collects no data; it is a fully local tool

## FAQ

**Q: Why not just use the App Store WireGuard app?**  
A: The official app does not run your `PostUp` / `PostDown` scripts; `wg-quick` does. This tool
is a GUI for exactly that workflow.

**Q: `wg-quick up` needs root — is it safe?**  
A: Yes. The privilege rule is scoped to two fixed commands via `sudoers.d`, and the UI never
runs arbitrary commands.

**Q: Where do configs live?**  
A: The app scans all of wg-quick's search paths: `/etc/wireguard`, `/usr/local/etc/wireguard`,
`/opt/homebrew/etc/wireguard`. Homebrew (Apple Silicon) configs usually live in
`/opt/homebrew/etc/wireguard/`.

**Q: The menu bar says connected but the detail window said stopped?**  
A: Fixed: the detail window now checks per-config status precisely and refreshes live with the
status poll. Update to the latest build.

**Q: Why is the interface `utun8` and not `fire`?**  
A: On macOS `wg-quick` uses the user-space `wireguard-go`, and the interface is dynamically
assigned as `utunN`. The config-name ↔ interface mapping is recorded at
`/var/run/wireguard/fire.name`; status detection relies on it.

## License

MIT — see [LICENSE](LICENSE).
