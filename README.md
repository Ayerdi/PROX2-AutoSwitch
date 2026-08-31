# Audio AutoSwitch

[![validate](https://github.com/Ayerdi/PROX2-AutoSwitch/actions/workflows/validate.yml/badge.svg)](https://github.com/Ayerdi/PROX2-AutoSwitch/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/Ayerdi/PROX2-AutoSwitch)](https://github.com/Ayerdi/PROX2-AutoSwitch/releases/latest)

Automatically switch the Windows default audio output when your wireless headset connects or disconnects.

**Stable release: [v1.5.0](https://github.com/Ayerdi/PROX2-AutoSwitch/releases/latest) · Windows 10/11 x64**

*Built with vibe coding — a solo project; its quirks are documented in [`AGENT.md`](AGENT.md).*

- Headset on / connected → use the headset.
- Headset off / disconnected → return to the configured fallback output.
- Three config modes remain backward compatible, with direct Centurion HID for Logitech PRO X 2 LIGHTSPEED (`046D:0AF7`) and the existing G HUB provider for other compatible Logitech headsets.
- Tray controls for AutoSwitch, reconfiguration and Windows Audio Enhancements; PRO X 2 also shows live battery percentage and connection state.
- Invisible startup: no PowerShell window at login.

![AutoSwitch demo: headset on selects the headset output, headset off returns to the speakers](site/autoswitch-demo.gif)

## Table of contents

**For users**

- [Quick start](#quick-start)
  - [Recommended: release ZIP](#recommended-release-zip)
  - [One-command install](#one-command-install)
- [Supported headsets](#supported-headsets)
- [How it works](#how-it-works)
  - [WindowsEndpoint](#windowsendpoint)
  - [Logitech PRO X 2 — Centurion HID](#logitech-pro-x-2--centurion-hid)
  - [LogitechGHub](#logitechghub)
  - [SteelSeriesNova5](#steelseriesnova5)
  - [Safety rules](#safety-rules)
- [Configuration](#configuration)
- [Tray and reconfiguration](#tray-and-reconfiguration)
- [Verify and uninstall](#verify-and-uninstall)
- [Troubleshooting](#troubleshooting)

**For operators**

- [Requirements](#requirements)
- [Installer behavior](#installer-behavior)
  - [Detection and validation](#detection-and-validation)
  - [Endpoint handling](#endpoint-handling)
  - [Installation and startup](#installation-and-startup)
- [Machine-local identifiers](#machine-local-identifiers)

**For contributors**

- [Project layout](#project-layout)
- [Development](#development)
- [Security](#security)
- [More resources](#more-resources)

**General**

- [Website & Wiki](#more-resources)
- [License](#license)

## Quick start

Same prerequisites as [Requirements](#requirements) — Windows 10/11 x64, PowerShell 5.1 or newer, no admin rights for normal use.

### Recommended: release ZIP

1. Open the [latest release](https://github.com/Ayerdi/PROX2-AutoSwitch/releases/latest).
2. Download **`Audio-AutoSwitch.zip`**.
3. Extract it to a normal folder.
4. Double-click **`Install.cmd`**.
5. Select the detection mode (see [Supported headsets](#supported-headsets)), headset and fallback output.
6. Follow the validation wizard: it asks you to turn the headset off and on, and confirms AutoSwitch follows each change.

The same package includes:

- **`Verify.cmd`** — run diagnostics.
- **`Uninstall.cmd`** — remove AutoSwitch.

The `.cmd` files are intentionally tiny launchers — the full PowerShell implementation ships in the package and is easy to inspect.

### One-command install

The bootstrap downloads the latest versioned release ZIP and checksum, verifies SHA-256, then starts the installer:

```powershell
powershell.exe -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/Ayerdi/PROX2-AutoSwitch/main/install.ps1 | iex"
```

## Supported headsets

| Headset | Detection mode | Extra software | Notes |
|---|---|---|---|
| Any headset whose Windows endpoint exposes connection state | `WindowsEndpoint` | None | Validated with a Jabra Evolve 65. |
| Logitech PRO X 2 LIGHTSPEED (`046D:0AF7`) | `LogitechGHub` (backward-compatible config name) | None for state detection | v1.5.0 reads the LIGHTSPEED receiver directly through Centurion HID and reports battery in the tray. |
| Other compatible Logitech headsets (including PRO X / PRO X Wireless) | `LogitechGHub` | Logitech G HUB (installed and running) | Keeps the existing local WebSocket battery provider. |
| SteelSeries Arctis Nova 5 / 5X | `SteelSeriesNova5` | None | Physical state read over HID; no SteelSeries GG required. |

See [How it works](#how-it-works) for the exact behavior of each mode.

## How it works

The installer chooses one of three detection modes.

### WindowsEndpoint

This is the general mode. It works when Windows exposes a meaningful state transition for the headset endpoint.

```text
Active                      → Connected    → headset
Unplugged / NotPresent      → Disconnected → fallback
Unknown / invalid reading   → no switch
```

Bluetooth can recreate the audio endpoint after a reconnect, so the installer and reconfiguration both wait for the real reconnect and then re-find the headset by its stable name. The underlying ID can change (see [Machine-local identifiers](#machine-local-identifiers)).

### Logitech PRO X 2 — Centurion HID

Starting with v1.5.0, Logitech PRO X 2 LIGHTSPEED no longer depends on G HUB's `/battery/<deviceId>/state` route for physical ON/OFF detection. G HUB 2026.5.939708 was observed returning `NO_SUCH_PATH` for that route while `/devices/list` continued to report the receiver as `ACTIVE` even when the headset was physically off.

AutoSwitch now talks directly to the PRO X 2 LIGHTSPEED receiver:

```text
PRO X 2 LIGHTSPEED receiver (VID 046D / PID 0AF7)
  ↓
vendor HID collection · UsagePage 0xFFA0 · 64-byte Centurion frames
  ↓
valid battery response → Connected + battery %
known power/off signature → Disconnected
anything else → Unknown → no switch
  ↓
two OFF observations → fallback
valid ON response → headset
```

The same battery value is exposed in the tray, for example `Battery: 76%`. The config continues to use `DetectionMode = LogitechGHub` for backward compatibility with existing installs, but the runtime automatically selects the direct Centurion provider for PRO X 2.

The direct provider was validated on real hardware on 2026-08-31 across repeated `ON → OFF → ON` cycles while G HUB was still running.

### LogitechGHub

Other compatible Logitech headsets still use the existing G HUB local WebSocket provider when Windows keeps their endpoint `Active` while the physical headset is off:

```text
compatible Logitech headset
  ↓
Logitech G HUB · ws://localhost:9010
  ↓
GET /devices/list
GET /battery/<deviceId>/state
  ↓
payload present → ON
payload absent  → OFF
```

The G HUB interface is unofficial and may change in a future G HUB release. PRO X 2 was moved to direct HID specifically to avoid relying on the route that changed in G HUB 2026.5.939708. See [`SOURCES.md`](SOURCES.md) and [`AGENT.md`](AGENT.md) for the verified design notes.

### SteelSeriesNova5

The Arctis Nova 5 / 5X receiver exposes the headset physical state over HID, so AutoSwitch reads it directly with no SteelSeries GG or third-party software:

```text
Arctis Nova 5 / 5X receiver
  ↓
HID (hid.dll / setupapi.dll) · P/Invoke
  ↓
status request → ON / OFF / Unknown
  ↓
Windows Core Audio / IPolicyConfig → all default roles
```

Use the bundled diagnostic tool to watch the receiver state live (run it from the extracted ZIP or the repo root; the tool is not copied to the installed runtime):

```powershell
.\tools\Test-SteelSeriesNova5Hid.ps1
```

### Safety rules

Two rules are deliberate:

1. An **unknown** state never changes the Windows output.
2. Disconnection needs **two consecutive OFF observations** before switching to the fallback.

A transient Core Audio, G HUB or HID failure therefore cannot send audio to the wrong device on a single bad read.

## Configuration

Runtime settings live in `%LOCALAPPDATA%\PROX2AutoSwitch\config.json` and are editable in place. The key fields:

| Field | Default | Meaning |
|---|---|---|
| `DetectionMode` | set by installer | `WindowsEndpoint`, `LogitechGHub` or `SteelSeriesNova5`. PRO X 2 keeps `LogitechGHub` as a backward-compatible config value but uses direct Centurion HID in v1.5.0. |
| `PollMilliseconds` | `1500` | Interval between state reads. |
| `OffMissThreshold` | `2` | Consecutive OFF reads before switching to the fallback. |
| `ConnectTimeoutMs` | `5000` | G HUB WebSocket connect timeout. |
| `DisableEnhancementsOnStart` | `false` | Whether Audio Enhancements are turned off for the headset at startup. |

The debounce has a practical consequence: `OffMissThreshold=2` × `PollMilliseconds=1500` delays the return to the fallback by about **1.5–3 s** (a maximum of about three seconds), depending on where in the poll cycle the headset turns off. Switching to the headset on power-up is immediate.

## Tray and reconfiguration

The tray menu shows the configured headset, fallback and next switch action. For PRO X 2 LIGHTSPEED it also shows direct HID connection state and live battery percentage.

![Real AutoSwitch tray menu with a Logitech PRO X 2 configured](site/assets/tray-menu.png)

It also provides:

- **AutoSwitch: Enabled / Disabled** — pause or resume switching. On PRO X 2, direct HID connection state and battery continue refreshing while switching is paused; audio outputs are never changed until AutoSwitch is enabled again.
- **Disable / Enable Audio Enhancements** — change the configured headset's global Windows enhancement state, with UAC only for the helper.
- **Reconfigure...** — choose new endpoints and repeat the complete detection wizard without reinstalling.
- **Exit** — stop AutoSwitch.

A failed reconfiguration leaves the previous working configuration untouched.

## Verify and uninstall

From an extracted release:

```text
Verify.cmd       (or .\Verify-AutoSwitch.ps1)
Uninstall.cmd    (or .\Uninstall-AutoSwitch.ps1)
```

The package also keeps the legacy Spanish-named `.ps1` entrypoints for existing shortcuts; this README uses the English aliases (see [Project layout](#project-layout)).

Installed runtime data and the main log live under:

```text
%LOCALAPPDATA%\PROX2AutoSwitch\
%LOCALAPPDATA%\PROX2AutoSwitch\autoswitch.log
```

## Troubleshooting

- **Bluetooth headset stopped switching after a reconnect.** The audio endpoint is recreated with a new internal ID after reconnecting. Run **Reconfigure...** to re-find it by name (see [Machine-local identifiers](#machine-local-identifiers)).
- **PRO X 2 stopped switching after a G HUB update.** Upgrade to v1.5.0 or newer. PRO X 2 now uses direct Centurion HID and no longer depends on G HUB's removed battery route. Run `Verify.cmd` to see the direct state and battery.
- **Another Logitech headset is on but the output stays on the speakers.** Its G HUB provider still needs Logitech G HUB installed and running; rerun the validation wizard.
- **Two devices share the same display name.** AutoSwitch resolves the current ID from the stable identity, so a copy of `config.json` from another PC is not supported (see [Machine-local identifiers](#machine-local-identifiers)).
- **Wondering what happened at runtime?** Run **`Verify.cmd`** or read `%LOCALAPPDATA%\PROX2AutoSwitch\autoswitch.log`.

## Requirements

- Windows 10/11 x64.
- PowerShell 5.1 or newer.
- No vendor software for `WindowsEndpoint` or `SteelSeriesNova5` headsets.
- Logitech G HUB installed and running for Logitech headsets that still use the G HUB provider. PRO X 2 LIGHTSPEED direct state detection does not require the G HUB battery API.

Normal runtime operation does not require administrator rights. Toggling global Windows Audio Enhancements uses a one-time UAC elevation for the helper process only.

## Installer behavior

The installer runs three phases — detection and validation, endpoint handling, and installation:

### Detection and validation

- Uses the Windows Core Audio APIs in-process, so no third-party audio-control executable is downloaded.
- Lists current Windows render devices and lets you choose the detection mode, headset and fallback.
- Validates the real `ON → OFF → ON` cycle with bounded polling windows of 15 s / 15 s / 20 s.
- Performs real test switches in both directions.

### Endpoint handling

- Handles a Bluetooth endpoint that returns with a new `Item ID`.
- For PRO X 2 LIGHTSPEED, checks the direct Centurion HID receiver when Windows cannot expose a useful physical state; other compatible Logitech headsets can fall back to G HUB.
- Captures machine-local Item IDs.

### Installation and startup

- Optionally disables Audio Enhancements for the headset.
- Installs the runtime under `%LOCALAPPDATA%`.
- Creates invisible per-user startup.
- Starts AutoSwitch.

If no supported detection method can be proven, installation stops instead of creating a configuration that cannot work.

## Machine-local identifiers

Windows audio `Item ID`s are machine-local and can change after driver changes or endpoint recreation. Do not copy `config.json` from another PC.

The G HUB `deviceId` is also not persisted because it may change. AutoSwitch keeps the stable display identity and resolves the current G HUB ID when needed.

## Project layout

```text
Install.cmd / Verify.cmd / Uninstall.cmd       double-click entrypoints
Install-AutoSwitch.ps1                         canonical installer alias
Verify-AutoSwitch.ps1                          canonical verifier alias
Uninstall-AutoSwitch.ps1                       canonical uninstaller alias
Instalar-* / Verificar-* / Desinstalar-*.ps1   legacy compatible entrypoints
Runtime-PROX2-AutoSwitch.ps1                   tray UI + worker runtime
Toggle-AudioEnhancements.ps1                   elevated enhancement helper
lib/AutoSwitchCore.psm1                        shared pure logic + COM interop
lib/LogitechProX2Centurion.psm1                 direct PRO X 2 HID + battery provider
lib/SteelSeriesNova5.psm1                      HID provider for Arctis Nova 5/5X
install.ps1                                    checksum-verifying bootstrap
tests/                                         Pester regression coverage
docs/                                          technical and historical notes
wiki/                                          versioned English + Spanish Wiki source
site/                                          GitHub Pages source
scripts/                                       release and repository tooling
```

## Development

Before opening a pull request, run the relevant Pester suite and keep the repository checks green. See [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`docs/INDEX.md`](docs/INDEX.md).

The project intentionally keeps hardware-specific findings and source references in [`AGENT.md`](AGENT.md) and [`SOURCES.md`](SOURCES.md) so future maintenance does not have to rediscover already-tested behavior.

## Security

- Audio endpoint enumeration and switching run in-process; installation downloads no third-party audio-control binary — the Windows audio APIs are called directly.
- Release ZIPs publish SHA-256 checksums and are built reproducibly.
- PRO X 2 state/battery is read locally from its HID receiver. The G HUB WebSocket remains local but unofficial for other Logitech providers; treat future compatibility changes as expected maintenance risk.
- Normal runtime is non-elevated; only the Audio Enhancements helper requests UAC.
- Please report security issues through the process in [`SECURITY.md`](SECURITY.md), not a public issue.

## More resources

- **Website:** https://ayerdi.github.io/PROX2-AutoSwitch/
- **Wiki (English):** https://github.com/Ayerdi/PROX2-AutoSwitch/wiki
- **Wiki (Spanish):** https://github.com/Ayerdi/PROX2-AutoSwitch/wiki/Inicio
- **[`SUPPORT.md`](SUPPORT.md)** — questions and non-security feedback.
- **[`CHANGELOG.md`](CHANGELOG.md)** — release history.
- **[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)** — contributor guidelines.

## License

MIT. See [`LICENSE`](LICENSE).
