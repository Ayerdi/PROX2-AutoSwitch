# SOURCES

Verified on August 7, 2026 (updated August 10, 2026).

## NirSoft — SoundVolumeCommandLine

Official docs:

https://www.nirsoft.net/utils/sound_volume_command_line.html

Relevant points:

- SoundVolumeCommandLine is the console version of SoundVolumeView.
- `/SetDefault [Name] [Default Type]` sets the default device.
- `all` sets Console, Multimedia and Communications.
- When several items share a name, `Item ID` or `Command-Line Friendly ID` can be used.
- `/GetColumnValue` returns the value of a column.
- `/Stdout` applied to `Set`-type commands shows the found items.
- `/scomma "<filename>"` exports the item list in CSV to stdout/file (with `/Columns` you can choose columns). We use `/scomma ""` to list all render items and read their `State`/`DeviceState` and `Item ID`.
- `/SetBooleanFxProperty` (v1.26+) toggles **individual** effects (Loudness Equalization, Headphone Virtualization, etc.). It is **NOT** the global "Disable audio enhancements" switch — do not use it for that.

## Audio enhancements — `PKEY_AudioEndpoint_Disable_SysFx`

- Property key: `{1da5d803-d492-4edd-8c23-e0c0ffee7f0e}, 5` (`PKEY_AudioEndpoint_Disable_SysFx`).
- Setting it to `1` disables the system effects of the endpoint (the "Disable audio enhancements" switch).
- Reading the value does not require elevation; **writing** it (via `IPolicyConfig::SetPropertyValue` on the FxStore) requires elevation (UAC).
- References:
  - https://learn.microsoft.com/en-us/windows/win32/coreaudio/pkey-audioendpoint-disable-sysfx
  - https://learn.microsoft.com/en-us/answers/questions/669471/how-to-control-enable-audio-enhancements-with-code (verified sample with `IPolicyConfig`, CLSID `870af99c-171d-4f9e-af0d-e63df40c2bc9`, IID `f8679f50-850a-41cf-9c72-430f290290c8`)
- **Win11 quirk**: on endpoints whose `FxProperties` value was never created, a non-elevated write cannot create it. The elevated `SetPropertyValue` is the mitigation; verify on Win11 before shipping.

## NirSoft — hashes

https://www.nirsoft.net/hash_check/?software=svcl

For `svcl-x64.zip`, checked on 2026-08-07:

```text
SHA256
7ba008e9ece8b3eda323ef01711e4647eb7f40b28dc25f98b2ed6a738810bfcd
```

## Logitech G HUB reverse-engineering reference

LGBattery:

https://github.com/bmrussell/LGBattery

Its README documents:

- WebSocket connection at `ws://localhost:9010`;
- headers;
- `GET /devices/list`;
- `payload.deviceInfos`;
- that `deviceInfos[].id` is not suitable for long-term persistence;
- use of `extendedDisplayName`;
- `SUBSCRIBE /battery/state/changed`.

This source **does not turn the G HUB API into an official Logitech API**. Treat it as an undocumented, potentially changing interface.

## PRO X 2 specific evidence

During the original AutoSwitch build, a controlled test was run on the target machine:

- PRO X 2 on: `GET /battery/<deviceId>/state` returned a battery payload.
- PRO X 2 off: several consecutive queries returned no payload.
- PRO X 2 back on: the payload returned.

That behavior is the basis for the runtime's ON/OFF detection and must be re-verified if a G HUB update changes it.
