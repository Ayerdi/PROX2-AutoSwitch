# SOURCES

Verified on August 7, 2026 (updated August 12, 2026).

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
- `/scomma "<filename>"` exports the item list in CSV to stdout/file (with `/Columns` you can choose columns). We use `/scomma ""` to list all items, filter `Type=Device` + `Direction=Render`, and read `Device State`, `Item ID`, `Device Name` and `Name`. `Device Name` and `Name` are separate columns and must not be conflated with the UI label `Device Name — Name`.
- `/SetBooleanFxProperty` (v1.26+) toggles **individual** effects (Loudness Equalization, Headphone Virtualization, etc.). It is **NOT** the global "Disable audio enhancements" switch — do not use it for that.

## Audio enhancements — `PKEY_AudioEndpoint_Disable_SysFx`

- Property key: `{1da5d803-d492-4edd-8c23-e0c0ffee7f0e}, 5` (`PKEY_AudioEndpoint_Disable_SysFx`).
- Setting it to `1` disables the system effects of the endpoint (the "Disable audio enhancements" switch).
- Reading the value does not require elevation; **writing** it (via `IPolicyConfig::SetPropertyValue` on the FxStore) requires elevation (UAC).
- **The value lives in the endpoint's FxStore**, reachable only through `IPolicyConfig` with `bFxStore=true`. The endpoint `IPropertyStore` (`IMMDevice::OpenPropertyStore`) does **not** contain it — reading it there always reports "enabled". This project reads it with `IPolicyConfig::GetPropertyValue(deviceId, true, ...)` in C# (see `AutoSwitch.EndpointFx.ReadSysFx`).
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

## WindowsEndpoint / Jabra hardware evidence

Project hardware tests on a Jabra Evolve 65:

- 2026-08-10: Windows exposed the render endpoint as `Active` while connected and `Unplugged` while powered off; returning ON restored `Active`. This validates the generic `WindowsEndpoint` path for that device.
- 2026-08-12: `Reconfigure...` was exercised from a PRO X 2 (`LogitechGHub`) configuration to the Jabra (`WindowsEndpoint`), followed by OFF → ON, process restart, and another OFF → ON. The runtime switched correctly and reloaded the new config.
- Bluetooth/Core Audio may take several seconds to report the final ON state. A diagnostic run timed out immediately before the next `svcl` read reported `Active`, which motivated bounded polling windows rather than fixed 500/800 ms sleeps.
- An `Item ID` observed in one cycle is **not a portable/stable identity guarantee**. The reconfigure path treats `Device Name` + `Name` as fallback identity only when the captured ID disappears, then persists the latest observed ID.

These are empirical project observations, not vendor guarantees for all Jabra/Bluetooth headsets.

## PRO X 2 specific evidence

During the original AutoSwitch build, a controlled test was run on the target machine:

- PRO X 2 on: `GET /battery/<deviceId>/state` returned a battery payload.
- PRO X 2 off: several consecutive queries returned no payload.
- PRO X 2 back on: the payload returned.

That behavior is the basis for the runtime's ON/OFF detection and must be re-verified if a G HUB update changes it.
