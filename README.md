# Audio AutoSwitch

[![Validate](https://github.com/Ayerdi/PROX2-AutoSwitch/actions/workflows/validate.yml/badge.svg)](https://github.com/Ayerdi/PROX2-AutoSwitch/actions/workflows/validate.yml)
[![Release](https://img.shields.io/github/v/release/Ayerdi/PROX2-AutoSwitch)](https://github.com/Ayerdi/PROX2-AutoSwitch/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Pages](https://github.com/Ayerdi/PROX2-AutoSwitch/actions/workflows/pages.yml/badge.svg)](https://github.com/Ayerdi/PROX2-AutoSwitch/actions/workflows/pages.yml)

**Automatically switch the Windows default audio output when a compatible wireless headset connects, disconnects, powers on or powers off.**

> **Stable release:** `v1.2.5` · Windows 10/11 x64 · Windows PowerShell 5.1+

[Website](https://ayerdi.github.io/PROX2-AutoSwitch/) · [Wiki](https://github.com/Ayerdi/PROX2-AutoSwitch/wiki) · [Docs](docs/INDEX.md) · [Releases](https://github.com/Ayerdi/PROX2-AutoSwitch/releases) · [Support](SUPPORT.md)

> The repository is English-first. The GitHub Wiki keeps a complete **English + Spanish** user guide.

![AutoSwitch demo](site/autoswitch-demo.gif)

## What it does

- **Headset ON / connected** → Windows selects the headset output.
- **Headset OFF / disconnected** → Windows selects the configured fallback output.
- **Unknown state** → nothing changes.
- **Tray controls** → pause/resume AutoSwitch, reconfigure devices, toggle Windows Audio Enhancements and exit.
- **Hidden startup** → no PowerShell console at login.

## Detection modes

### `WindowsEndpoint`

The general path for headsets whose Windows render endpoint exposes a useful connection-state transition. A tested Jabra Evolve 65 reports `Active ↔ Unplugged`.

### `LogitechGHub`

A device-specific fallback for Logitech PRO X 2, whose Windows endpoint can remain `Active` while the physical headset is off. AutoSwitch uses G HUB's **unofficial local WebSocket** (`ws://localhost:9010`) as the physical ON/OFF signal.

The G HUB interface is reverse-engineered, not an official Logitech API, and may change in future G HUB releases.

## Safety rules

- `Unknown` never changes the output.
- Disconnection requires consecutive OFF readings.
- G HUB requests and socket close operations have bounded timeouts.
- Bluetooth endpoint recreation is handled by re-resolving the real `Device Name` + `Name` identity when the Item ID changes.
- The installer aborts rather than pretending a headset is compatible when it cannot observe a safe signal.
- Downloaded release packages and NirSoft `svcl.exe` are verified with SHA-256 before execution.

## Requirements

- Windows 10/11 x64.
- PowerShell 5.1 or newer.
- Internet access during installation to download `svcl.exe` from NirSoft.
- Logitech G HUB only for the PRO X 2 fallback path.

Normal runtime is not elevated. Toggling Audio Enhancements launches a narrowly scoped helper and triggers UAC only for that operation.

## Recommended installation

Download **`Audio-AutoSwitch.zip`** and its `.sha256` from the [latest release](https://github.com/Ayerdi/PROX2-AutoSwitch/releases/latest), verify the checksum, extract the entire ZIP and double-click:

```text
Install.cmd
```

The installer lists the headset/fallback, observes a real ON → OFF → ON cycle and chooses the safe detection mode automatically.

### One-command bootstrap

```powershell
powershell.exe -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/Ayerdi/PROX2-AutoSwitch/main/install.ps1 | iex"
```

### PowerShell entrypoints

For users who prefer PowerShell directly:

```powershell
.\Install-AutoSwitch.ps1
.\Verify-AutoSwitch.ps1
.\Uninstall-AutoSwitch.ps1
```

The original Spanish-named `.ps1` files remain as compatibility implementations so existing shortcuts/scripts do not break.

## Tray and reconfiguration

![Real AutoSwitch tray menu](site/assets/tray-menu.png)

The tray shows the configured headset, fallback and expected next switch. `Reconfigure...` validates a fresh ON → OFF → ON sequence. Bluetooth/Core Audio transitions are polled within bounded windows (15 s / 15 s / 20 s), and a recreated endpoint can be matched by its stable Windows identity and assigned its new Item ID.

## Verify and uninstall

Double-click:

```text
Verify.cmd
Uninstall.cmd
```

or use the canonical PowerShell aliases shown above.

Installed data lives under:

```text
%LOCALAPPDATA%\PROX2AutoSwitch\
```

Log:

```text
%LOCALAPPDATA%\PROX2AutoSwitch\autoswitch.log
```

## Important implementation note

`svcl.exe /GetColumnValue` already writes the requested value to stdout. Do **not** prepend `/Stdout`; an older implementation polluted the Item ID and broke `/SetDefault`.

## Technical evidence and maintenance

- [SOURCES.md](SOURCES.md) — verified NirSoft/Microsoft references and real-hardware evidence.
- [SECURITY.md](SECURITY.md) — trust boundaries and private reporting.
- [AGENT.md](AGENT.md) — maintainer context and invariants.
- [docs/WindowsEndpointProvider.md](docs/WindowsEndpointProvider.md) — historical endpoint-provider design and corrected assumptions.
- [CONTRIBUTING.md](CONTRIBUTING.md) — contribution rules and validation.

## Repository layout

- `Install.cmd`, `Verify.cmd`, `Uninstall.cmd` — easiest user entrypoints.
- `Install-AutoSwitch.ps1`, `Verify-AutoSwitch.ps1`, `Uninstall-AutoSwitch.ps1` — canonical English PowerShell entrypoints.
- legacy Spanish-named `.ps1` files — compatibility implementations.
- `Runtime-PROX2-AutoSwitch.ps1` — tray UI and worker runtime.
- `Toggle-AudioEnhancements.ps1` — elevated enhancements helper.
- `lib/AutoSwitchCore.psm1` — shared pure logic and Core Audio interop.
- `tests/` — Pester regression coverage.
- `site/` — GitHub Pages.
- `wiki/` — authoritative English + Spanish Wiki source.

## License

[MIT](LICENSE).
