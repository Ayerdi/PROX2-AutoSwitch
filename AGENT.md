# AGENT.md — maintaining Audio AutoSwitch

## Goal

Maintain a Windows solution that automatically switches the default audio output:

- Wireless headset physically powered on / connected → headset endpoint.
- Wireless headset powered off / disconnected → configured alternative endpoint.

The tool is universal: it works with **any headset whose connection state is exposed by Windows**
(`DetectionMode = WindowsEndpoint`), with a device-specific fallback (`DetectionMode = LogitechGHub`)
for Logitech headsets such as the PRO X 2 whose endpoint stays `Active` while off.

The LIGHTSPEED receiver stays connected, so you **cannot** use the presence of the USB/PnP endpoint as an on/off signal for the PRO X 2.

## Detection modes (config `DetectionMode`)

- `WindowsEndpoint` (default for new installs): read the headset endpoint `State` from the
  native Core Audio endpoint list and map it:
  - `Active` → `Connected` → headset.
  - `Unplugged` / `NotPresent` / row absent → `Disconnected` → fallback.
  - `Disabled` / `Error` / unparseable → `Unknown` → **never switch**.
- `LogitechGHub`: existing G HUB WebSocket path (payload present = ON, absent = OFF), debounce applied.
- Config without `DetectionMode` is treated as `LogitechGHub` (backward compat); the runtime migrates
  the config file to v1.2.0 on first run, preserving all values.

## Verified design state

On the original machine, 2026-08-07:

- G HUB was available at `ws://localhost:9010`.
- `/devices/list` returned `PRO X 2 Lightspeed Gaming Headset`.
- The observed `deviceId` had the form `dev00000000`.
- `GET /battery/<deviceId>/state`:
  - returned a payload while the headset was powered on;
  - stopped returning a payload when powered off;
  - returned a payload again when powered back on.

Do not persist `dev000000XX`: it can change. Persist `extendedDisplayName` and resolve the current ID via `/devices/list`.

On 2026-08-10, the universal path was validated with a **Jabra Evolve 65**: Windows exposed
`Active ↔ Unplugged`, so no vendor software is needed. The first controlled cycles happened to keep
the same `Item ID`, but **do not treat that as a guarantee**. On 2026-08-12, Reconfigure testing showed
that Bluetooth/Core Audio can take several seconds to recreate/report the endpoint, and the design was
hardened to tolerate a recreated endpoint whose `Item ID` changes.

## Design constraints

1. Do not hardcode Windows Item IDs.
   - They change after reinstalling Windows, drivers or recreating endpoints.
   - The installer must capture the IDs of the current system.

2. For duplicated endpoints, use `Item ID` for normal runtime targeting. During **Reconfigure only**,
   if that ID disappears after a Bluetooth reconnect, re-resolve the endpoint by the two native endpoint identity properties
   (`PKEY_DeviceInterface_FriendlyName` + `PKEY_Device_DeviceDesc`) and then persist the newly observed `Item ID`. Never use
   the combined display label as if it were a raw column value.

3. To set the output, use the in-process Core Audio bridge in `lib/AutoSwitchCore.psm1`.
   `Set-CoreAudioDefaultRenderDevice` applies the target to Console, Multimedia and Communications.

4. To read the current defaults, use `Get-CoreAudioDefaultRenderDeviceIds`.
   Do not infer success from the setter alone.

5. Verify every switch:
   - set all three roles;
   - re-read Console, Multimedia and Communications;
   - require every role to match the target;
   - allow a single short retry.

6. Unknown state (Core Audio failure, `Disabled`, unmapped state):
   - do not guess the state;
   - do not switch the output;
   - write a log entry;
   - retry next poll.

7. Power-off / disconnect:
   - require at least 2 consecutive OFF readings (`OffMissThreshold=2`) before switching to the fallback.

8. Avoid windows at login:
   - use `wscript.exe` + `Iniciar-Oculto.vbs`;
   - the Startup shortcut must point to `wscript.exe`, not directly to PowerShell.

9. Avoid duplicate instances:
   - per-user mutex.

10. **Runtime loop**: the polling runs in a **separate worker process**
    (`AUTOSWITCH_WORKER=1`, same script re-executed) so the WinForms message pump
    (`Application.Run()` over an invisible main `Form`) and the tray icon stay responsive.
    The worker is a single synchronous loop (`Start-Sleep PollMilliseconds`), which is itself the guard
    against concurrent polls — it never starts a new poll while the previous one is still running.
    The main process communicates via control flags (`control/enabled.flag`, `control/stop.flag`).
    Do NOT run Core Audio/G HUB/Set-AudioOutput on the UI thread. Pass `[System.Windows.Forms.Application]::Run($form)`
    an invisible `Form`; `Application.Run()` without a Form is not reliably kept alive across all .NET builds.

11. **Audio Enhancements**: toggled only for the configured `HeadsetId` via a temporary elevated
    helper (`Toggle-AudioEnhancements.ps1`, `Start-Process -Verb RunAs`) that writes
    `PKEY_AudioEndpoint_Disable_SysFx` (1da5d803-d492-4edd-8c23-e0c0ffee7f0e, 5) through
    `IPolicyConfig::SetPropertyValue(deviceId, bFxStore=true)`, verifies, and exits. The runtime itself
    is never elevated. The menu label updates only after a verified success (UAC cancel → no visual change).

12. **COM interop lives in C#**: PowerShell 5.1 cannot cast a COM RCW to a custom `[ComImport]` interface
    (`New-Object`, `Activator` or `GetTypeFromCLSID` all fail with "the COM interface cast fails at runtime"). The cast is
    native in C#, so both the helper and `lib/AutoSwitchCore.psm1` compile the whole COM block with
    `Add-Type` and expose static methods for endpoint enumeration/default switching and enhancements. Read the SysFx state with `IPolicyConfig::GetPropertyValue` on the
    **FxStore** (`bFxStore=true`) — the endpoint `IPropertyStore` does **not** contain
    `PKEY_AudioEndpoint_Disable_SysFx`, so reading it there always reports "enabled".

13. **`Add-Type` sentinel**: guard with a type that is actually declared in the block (e.g.
    `AutoSwitch.EndpointFx`). Using a non-existent sentinel makes the compiler re-run on every call and
    fail on the second one.

14. **Paths**: launch the worker with `$PSCommandPath` (captured once as `$script:RuntimePath` at the top
    of the runtime). `$MyInvocation.MyCommand.Path` inside a function can be empty in PS 5.1. Files with
    non-ASCII characters must be saved with a UTF-8 BOM (PSScriptAnalyzer requirement).

15. **Reconfigure identity and timing**:
    - validation cycle is `Connected → Disconnected → Connected`;
    - poll every 500 ms with bounded waits (15 s first ON, 15 s OFF, 20 s final ON);
    - if `Item ID` disappears, match **both** `Device Name` and `Name` when available;
    - prefer the final-ON observed ID and save it to `config.json`;
    - if detection cannot be proven, leave the existing config untouched.

## Local G HUB API used

WebSocket:

```text
ws://localhost:9010
```

Headers observed/used:

```text
Origin: file://
Pragma: no-cache
Cache-Control: no-cache
Sec-WebSocket-Extensions: permessage-deflate; client_max_window_bits
Sec-WebSocket-Protocol: json
```

List devices:

```json
{
  "msgId": "<guid>",
  "verb": "GET",
  "path": "/devices/list"
}
```

The response contains:

```text
payload.deviceInfos[]
```

Useful fields:

```text
id
extendedDisplayName
deviceType
capabilities.hasBatteryStatus
```

Query used by this project:

```text
GET /battery/<deviceId>/state
```

The reference project LGBattery also documents a subscription to:

```text
SUBSCRIBE /battery/state/changed
```

To evolve the runtime, one option is to use WebSocket events and keep polling as a fallback. Do not change it without testing power-on, power-off, G HUB restart, sleep and a clean login.

## Native Core Audio backend

- `IMMDeviceEnumerator` / `IMMDevice` enumerate render endpoints, states and endpoint IDs.
- `IPropertyStore` reads `PKEY_Device_DeviceDesc`, `PKEY_DeviceInterface_FriendlyName` and `PKEY_Device_FriendlyName`.
- `IPolicyConfig::SetDefaultEndpoint` is used for Console, Multimedia and Communications, then all three roles are re-read and verified.
- `IPolicyConfig` is not a documented public Windows API. This project already depended on the same COM family for Audio Enhancements; keep the boundary isolated in embedded C# and fail safely on HRESULT errors.
- Clean install no longer downloads or hashes a third-party audio-control executable.

## Required tests after any change

### Clean install — universal (WindowsEndpoint)

- No G HUB needed.
- Pick headset + fallback from the endpoint list.
- Auto-detect: `Active → Unplugged` observed → `WindowsEndpoint`.
- IDs are different.
- Test `fallback -> headset` = OK.
- Test `headset -> fallback` = OK.

### Clean install — Logitech (LogitechGHub)

- G HUB open.
- PRO X 2 detected.
- Capture headset endpoint.
- Capture alternative endpoint.
- IDs are different.
- Test `speaker -> headset` = OK.
- Test `headset -> speaker` = OK.

### Runtime

- Start with headset ON / connected.
- Start with headset OFF / disconnected.
- ON → OFF.
- OFF → ON.
- Close/reopen G HUB (Logitech mode).
- Log out and back in.
- Confirm no PowerShell window appears.
- Confirm no duplicate processes.
- Confirm the tray icon stays responsive while polling (Timer-driven).
- Confirm reasonable log.

### Reconfigure (required after endpoint/detection changes)

- `WindowsEndpoint → WindowsEndpoint`: ON → OFF → ON succeeds.
- `LogitechGHub → WindowsEndpoint` (validated with Jabra Evolve 65): mode changes and worker reloads config.
- `WindowsEndpoint → LogitechGHub`: G HUB association and port are created correctly.
- Exit/start after reconfigure and repeat OFF → ON.
- Simulate a recreated Bluetooth row with the same `Device Name` + `Name` but a different `Item ID`; the identity matcher must select that exact Render endpoint and persist the new ID.
- If one physical device exposes multiple Render endpoints, identity matching must not pick the wrong `Name`.

### Enhancements

- Menu shows "Disable for …" when enabled; after verified disable, flips to "Enable for …".
- Cancel UAC → label unchanged.
- With the headset OFF and speakers as default, toggling still modifies the headset endpoint (`HeadsetId`).

### Failure cases

- G HUB closed (Logitech mode): do not switch output.
- Endpoint removed/recreated during Reconfigure: re-resolve by `Device Name` + `Name`, persist the newest ID, and fail without changing config if identity is ambiguous/missing. A runtime endpoint that disappears outside Reconfigure remains a diagnostic/reconfigure case; never guess a target.
- `/devices/list` does not contain the PRO X 2: fall back to WindowsEndpoint path; do not invent a `deviceId`.
- Core Audio enumeration/state read fails or is `Disabled`/unmapped: `Unknown`, do not switch.

## Possible future improvements

- Event-driven `IMMNotificationClient` for instant `Active ↔ Unplugged` (could replace the 1.5 s polling; the COM interop pattern in `lib/AutoSwitchCore.psm1` already compiles C#).
- Subscribe to `/battery/state/changed` to reduce polling.
- More vendor-specific providers (Jabra Direct, BT APIs) for headsets Windows cannot detect.
- Settings GUI (per-device config).
- Scheduled task as an alternative to Startup+WScript if VBScript disappears from future Windows versions.
- Repo rename to "Audio AutoSwitch" (update install.ps1 URLs in README/site).

## Do not assume

- Do not assume all Logitech devices behave the same.
- Do not assume `deviceId` is stable.
- Do not assume speaker names will always be the same.
- Do not assume the Item ID survives a format, driver change, endpoint recreation or Bluetooth reconnect.
- Do not assume the G HUB API is officially supported.


## v1.5.0 PRO X 2 Centurion provider (verified 2026-08-31)

G HUB `2026.5.939708` stopped exposing the PRO X 2 `/battery/<deviceId>/state` route (`NO_SUCH_PATH`) while `/devices/list` remained `ACTIVE` even with the headset physically OFF. v1.5.0 therefore keeps `DetectionMode = LogitechGHub` for backward-compatible configs but automatically prefers `lib/LogitechProX2Centurion.psm1` when the configured device is a PRO X 2.

Verified receiver details: Logitech `046D:0AF7`, UsagePage `0xFFA0`, Usage `0x0001`, 64-byte reports. Connected queries return a valid battery response; the tested OFF state repeatedly emitted `51 05 00 FF 03 1A 0B 00 ...`. Unrecognized/malformed/time-out results are `Unknown` and never switch. The existing outer OFF debounce remains mandatory.

End-to-end hardware validation on 2026-08-31 completed two real OFF/ON cycles: two confirmed OFF observations selected the fallback and the next valid battery reply selected the PRO X 2. The same provider supplies battery percentage to the tray.
