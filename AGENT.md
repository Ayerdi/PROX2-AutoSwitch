# AGENT.md — maintaining Audio AutoSwitch

## Goal

Maintain a Windows solution that automatically changes the default render endpoint when a compatible wireless headset is physically available:

- headset ON / connected → configured headset endpoint;
- headset OFF / disconnected → configured fallback endpoint;
- provider state `Unknown` → **never change audio**.

The project uses provider-specific physical-state detection while keeping Windows Core Audio as the single output-switching backend.

## Canonical provider architecture (v1.5.0)

### `WindowsEndpoint`

General provider for headsets whose Windows render endpoint exposes a useful physical transition.

- `Active` → `Connected`.
- `Unplugged`, `NotPresent` or endpoint absent → `Disconnected`.
- `Disabled`, read failure or unmapped state → `Unknown`.

This path was validated on a Jabra Evolve 65. No vendor software is required.

### `LogitechGHub` — backward-compatible config family

`DetectionMode = LogitechGHub` remains the persisted config value for Logitech installations so existing configurations keep working, but the runtime now chooses the physical-state provider inside that family:

1. **Logitech PRO X 2 LIGHTSPEED** → direct **Centurion HID** through `lib/LogitechProX2Centurion.psm1`.
2. Other compatible Logitech headsets → legacy G HUB local WebSocket provider when their battery route is available.

Do **not** describe PRO X 2 v1.5.0 as using G HUB for ON/OFF detection. G HUB may remain installed/running, but the PRO X 2 state and battery signal come directly from its LIGHTSPEED receiver.

### `SteelSeriesNova5`

SteelSeries Arctis Nova 5/5X physical state is read directly over HID through `lib/SteelSeriesNova5.psm1`. SteelSeries GG is not required for this provider.

## Why PRO X 2 changed in v1.5.0

Original behavior verified on 2026-08-07:

- G HUB was reachable at `ws://localhost:9010`.
- `/devices/list` returned `PRO X 2 Lightspeed Gaming Headset`.
- `GET /battery/<deviceId>/state` returned a payload while ON, stopped returning one while OFF, and returned again after power-on.

Regression verified on 2026-08-31 with G HUB `2026.5.939708`:

- `/devices/list` still reported the PRO X 2 as `ACTIVE` with `resourcesAvailable=true` while the headset was physically OFF;
- `GET /battery/<deviceId>/state` returned `NO_SUCH_PATH`;
- the Windows audio endpoint also remained `Active` while the physical headset was OFF.

Therefore neither the Windows endpoint nor the old G HUB battery route is a reliable PRO X 2 physical-state signal on that G HUB build.

## PRO X 2 Centurion HID provider

Verified target receiver/interface:

```text
VID:       0x046D
PID:       0x0AF7
UsagePage: 0xFFA0
Usage:     0x0001
Reports:   64-byte input/output on tested hardware
```

The module enumerates HID interfaces with SetupAPI, verifies VID/PID and HID caps, opens the vendor collection with shared read/write access, then sends the Centurion battery request.

A valid connected reply has the expected `0x51 0x0B ...` structure and exposes battery percentage at byte 10. Battery values in the real end-to-end test included 70% and 76%.

The physical OFF state repeatedly produced this tested signature:

```text
51 05 00 FF 03 1A 0B 00 ...
```

Provider mapping:

- valid battery response → `Connected` + `BatteryPercent`;
- tested OFF signature → `Disconnected` observation;
- endpoint missing, timeout, malformed/unrecognized frame, open/read/write error → `Unknown`.

The exact OFF signature is hardware evidence, not a general Logitech guarantee. Do not broaden it without a real capture and regression test.

The PowerShell runtime still applies the normal outer OFF debounce (`OffMissThreshold`, default 2) before selecting the fallback. A single disconnected observation must not immediately move audio.

## Tray telemetry

The worker writes provider telemetry to:

```text
%LOCALAPPDATA%\PROX2AutoSwitch\control\headset-status.json
```

Fields include provider, physical state, battery percentage and timestamp. The WinForms tray reads this small file instead of performing HID/G HUB I/O on the UI thread.

For PRO X 2:

- connected → tray shows physical state and live battery percentage;
- disconnected → tray removes the stale percentage;
- unknown/stale status → tray shows an unknown state rather than inventing a value.

When `AutoSwitch: Disabled`, PRO X 2 Centurion polling **continues only for tray telemetry**. The worker resets switching history and does not call `Resolve-HeadsetState` / `Set-AudioOutput` until AutoSwitch is enabled again.

## G HUB fallback for other Logitech headsets

The legacy provider still uses the undocumented localhost WebSocket:

```text
ws://localhost:9010
```

Observed headers:

```text
Origin: file://
Pragma: no-cache
Cache-Control: no-cache
Sec-WebSocket-Extensions: permessage-deflate; client_max_window_bits
Sec-WebSocket-Protocol: json
```

Device discovery:

```json
{
  "msgId": "<guid>",
  "verb": "GET",
  "path": "/devices/list"
}
```

Useful response fields include `id`, `extendedDisplayName`, `deviceType` and `capabilities.hasBatteryStatus`.

For non-PRO-X-2 Logitech headsets whose route exists, runtime may query:

```text
GET /battery/<deviceId>/state
```

Never persist a volatile G HUB `deviceId`; resolve it again from `/devices/list`. Treat connection/request failures as `Unknown`, close the socket with bounded timeouts, and retry later.

The G HUB interface is unofficial and may change without notice. Never assume the removed PRO X 2 route has returned merely because `/devices/list` works.

## Windows Core Audio backend

All output enumeration, identity/state reads and switching are centralized in `lib/AutoSwitchCore.psm1`.

- `IMMDeviceEnumerator` / `IMMDevice` enumerate render endpoints and states.
- `IPropertyStore` reads endpoint identity properties.
- `Get-CoreAudioDefaultRenderDeviceIds` reads the current defaults.
- `Set-CoreAudioDefaultRenderDevice` applies Console, Multimedia and Communications using the isolated `IPolicyConfig::SetDefaultEndpoint` compatibility boundary.

`IPolicyConfig` is undocumented. Treat HRESULT failures as errors, verify all three roles after every switch and allow only the existing bounded retry.

Do not reintroduce `svcl.exe` or another downloaded audio-control executable.

## Endpoint identity rules

1. Never hardcode Windows Item IDs.
2. Runtime targets the stored Item ID normally.
3. During Reconfigure, Bluetooth may recreate an endpoint with a different Item ID.
4. If the stored ID disappears during Reconfigure, match the two native identity values (`Device Name` + `Name`) when available.
5. Persist the newest observed Item ID after a successful final ON state.
6. Never treat the combined display label as a raw identity property.
7. If identity is ambiguous or cannot be proven, keep the existing configuration unchanged.

## Runtime architecture and safety invariants

The tray and polling loop are separate processes.

- Main process: WinForms message pump + tray only.
- Worker: same runtime script launched with `AUTOSWITCH_WORKER=1`.
- Control files: `enabled.flag`, `stop.flag`, `reload.flag` and provider-status JSON under `control/`.
- Per-user mutex prevents duplicate main instances.
- Worker is a single synchronous loop; do not introduce overlapping provider polls.

Mandatory invariants:

1. `Unknown` never changes output.
2. OFF requires consecutive confirmed observations.
3. Provider I/O must not run on the tray/UI thread.
4. Every output change must be verified across Console, Multimedia and Communications.
5. Reconfigure failure must leave the previous config intact.
6. The normal runtime remains non-elevated.
7. Audio Enhancements elevation is isolated to `Toggle-AudioEnhancements.ps1`.
8. G HUB network operations keep bounded connect/send/receive/request/close timeouts.
9. Direct HID errors are local provider failures, not evidence that the headset is OFF.
10. When AutoSwitch is paused, telemetry may continue but audio switching must not.

## PowerShell / COM constraints

- Target Windows PowerShell 5.1 compatibility.
- Launch the worker from the captured `$PSCommandPath`; `$MyInvocation.MyCommand.Path` may be empty inside functions.
- Non-ASCII PowerShell source/test files require UTF-8 BOM for the validation toolchain.
- Core Audio COM interfaces are implemented in embedded C# because PowerShell 5.1 cannot reliably cast COM RCWs to custom `[ComImport]` interfaces.
- Guard `Add-Type` blocks with a type that actually exists in the compiled block.
- Enhancements state must be read from the FxStore with `IPolicyConfig::GetPropertyValue(..., bFxStore=true)`.

## Installer and Reconfigure

Installer headset choices in v1.5.0:

1. standard wireless headset → `WindowsEndpoint`;
2. Logitech headset → try PRO X 2 Centurion direct HID first, then G HUB for other compatible Logitech headsets;
3. auto-detect → validate the real ON → OFF → ON cycle and choose a compatible provider;
4. SteelSeries Nova 5/5X → direct SteelSeries HID provider.

A clean v1.5.0 install must write `Version = 1.5.0` to `config.json`.

Reconfigure keeps the same safe model: prove the provider before saving, preserve the old config on failure, then signal the worker through `reload.flag`.

## Required validation after provider/runtime changes

### Automated

The PR must pass all of these:

- repository-quality checks;
- English canonical-language guard;
- deterministic release build twice with byte comparison;
- PowerShell parser;
- PSScriptAnalyzer;
- Pester;
- Gitleaks;
- aggregate `validate` check.

### PRO X 2 hardware

At minimum:

1. headset ON → direct provider reports `Connected` and plausible battery;
2. ON → OFF with receiver still attached → confirmed OFF samples select fallback only after debounce;
3. OFF → ON → valid battery reply selects headset;
4. repeat a second full cycle;
5. pause AutoSwitch → state/battery continue updating but output never changes;
6. re-enable AutoSwitch → switching resumes from a clean observation;
7. restart runtime and repeat OFF → ON;
8. keep G HUB running during at least one test to verify coexistence.

The v1.5.0 implementation was hardware-validated for two complete OFF/ON switching cycles on 2026-08-31. The pause-telemetry behavior is additionally enforced by control-flow gating and CI; re-test it on hardware when convenient.

### WindowsEndpoint regression

- ON → OFF → ON on a device whose endpoint genuinely transitions.
- Recreated Bluetooth endpoint resolves by native identity and stores the new Item ID.

### Other Logitech regression

- A non-PRO-X-2 Logitech headset must not be selected by the Centurion provider.
- If its G HUB battery route exists, G HUB mode continues to work.
- If G HUB is unavailable/changed, state becomes `Unknown`; do not switch.

### SteelSeries regression

- Nova 5/5X HID state remains functional and independent of Logitech changes.

## Release and repository policy

- Build packages with `scripts/build-release.sh <version>`.
- Versioned ZIP and stable `Audio-AutoSwitch.zip` must be byte-identical and have SHA-256 files.
- Versioned release workflows are one-shot publishers; do not keep a generic permanent `release.yml`.
- Versioned Wiki source under `wiki/` must be synchronized to the public GitHub Wiki for a release.
- GitHub Pages is built from `site/`.
- `scripts/configure-public-repository.sh` is the versioned source of truth for public repository settings. For this solo project it intentionally requires the component CI checks and conversation resolution but **0 approving reviews**; do not silently drift the live branch protection away from that policy.

## Do not assume

- Do not assume all Logitech devices use the same protocol.
- Do not assume the PRO X 2 G HUB battery route exists.
- Do not assume G HUB `deviceId` is stable.
- Do not assume the receiver's USB presence means the headset is powered on.
- Do not assume a failed HID query means OFF.
- Do not assume Windows Item IDs survive driver changes, endpoint recreation or reinstall.
- Do not assume `IPolicyConfig` or the G HUB API is officially supported.
- Do not broaden hardware-specific signatures without captures and real-device validation.
