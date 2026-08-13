# SOURCES

Verified on August 7, 2026 (updated August 12, 2026).



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


## Windows Core Audio endpoint APIs

- Microsoft Learn — `IMMDeviceEnumerator::EnumAudioEndpoints`: documents render/capture endpoint enumeration and device-state masks.
  https://learn.microsoft.com/windows/win32/api/mmdeviceapi/nf-mmdeviceapi-immdeviceenumerator-enumaudioendpoints
- Microsoft Learn — Core Audio device properties: documents `PKEY_DeviceInterface_FriendlyName`, `PKEY_Device_DeviceDesc`, `PKEY_Device_FriendlyName`, endpoint IDs and container IDs.
  https://learn.microsoft.com/windows/win32/coreaudio/device-properties
- Microsoft Learn — `IMMDeviceEnumerator::GetDefaultAudioEndpoint`: documents reading the current default endpoint by role.
  https://learn.microsoft.com/windows/win32/api/mmdeviceapi/nf-mmdeviceapi-immdeviceenumerator-getdefaultaudioendpoint

`IPolicyConfig::SetDefaultEndpoint` is an undocumented Windows COM interface. It is intentionally isolated inside the embedded C# bridge and is treated as a compatibility risk, not as a supported Microsoft API.
