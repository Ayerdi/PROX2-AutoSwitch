# SOURCES

Verified on August 7, 2026.

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
