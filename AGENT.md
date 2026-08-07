# AGENT.md — maintaining PRO X 2 AutoSwitch

## Goal

Maintain a Windows solution that automatically switches the default audio output:

- PRO X 2 physically powered on → headset endpoint.
- PRO X 2 physically powered off → configured alternative endpoint.

The LIGHTSPEED receiver stays connected, so you **cannot** use the presence of the USB/PnP endpoint as an on/off signal.

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

## Design constraints

1. Do not hardcode Windows Item IDs.
   - They change after reinstalling Windows, drivers or recreating endpoints.
   - The installer must capture the IDs of the current system.

2. For duplicated endpoints, use `Item ID`, not just `Name`.

3. To set the output:
   ```powershell
   svcl.exe /SetDefault "<Item ID>" all
   ```
   `all` covers Console, Multimedia and Communications.

4. To read a column:
   ```powershell
   svcl.exe /GetColumnValue "DefaultRenderDevice" "Item ID"
   ```
   **Do NOT add `/Stdout`** to `/GetColumnValue`.

5. Verify the switch:
   - run `/SetDefault`;
   - re-read `DefaultRenderDevice` → `Item ID`;
   - compare with the target;
   - allow a single short retry.

6. G HUB unavailable:
   - do not guess the state;
   - do not switch the output;
   - write a log entry;
   - retry every 5 s.

7. Power-off:
   - require at least 2 consecutive payload-less responses (`OffMissThreshold=2`) before switching to speakers.

8. Avoid windows at login:
   - use `wscript.exe` + `Iniciar-Oculto.vbs`;
   - the Startup shortcut must point to `wscript.exe`, not directly to PowerShell.

9. Avoid duplicate instances:
   - per-user mutex.

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

## SoundVolumeCommandLine

Provider: NirSoft.

Current x64 URL in this package's version:

```text
https://www.nirsoft.net/utils/svcl-x64.zip
```

SHA-256 verified on 2026-08-07:

```text
7ba008e9ece8b3eda323ef01711e4647eb7f40b28dc25f98b2ed6a738810bfcd
```

Before changing the hash:
1. check the official hashes page;
2. confirm it matches `svcl-x64.zip` exactly;
3. update the comment/date;
4. do not disable the check.

## Required tests after any change

### Clean install

- G HUB open.
- PRO X 2 detected.
- Capture headset endpoint.
- Capture alternative endpoint.
- IDs are different.
- Test `speaker -> headset` = OK.
- Test `headset -> speaker` = OK.

### Runtime

- Start with headset ON.
- Start with headset OFF.
- ON → OFF.
- OFF → ON.
- Close/reopen G HUB.
- Log out and back in.
- Confirm no PowerShell window appears.
- Confirm no duplicate processes.
- Confirm reasonable log.

### Failure cases

- G HUB closed: do not switch output.
- Endpoint removed/recreated: log SetDefault failure; ask for reinstall/recalibration.
- NirSoft hash differs: abort install.
- `/devices/list` does not contain the PRO X 2: show the list and abort; do not invent a `deviceId`.

## Possible future improvements

- Subscribe to `/battery/state/changed` to reduce polling.
- Tray UI to pause/change outputs.
- Recalibration without reinstalling.
- Support for other Logitech headsets after validating the battery signal on power-off.
- Scheduled task as an alternative to Startup+WScript if VBScript disappears from future Windows versions.

## Do not assume

- Do not assume all Logitech devices behave the same.
- Do not assume `deviceId` is stable.
- Do not assume speaker names will always be the same.
- Do not assume the Item ID survives a format.
- Do not assume the G HUB API is officially supported.
