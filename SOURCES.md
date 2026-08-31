# SOURCES

Verified on August 7, 2026 (updated August 31, 2026).



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
- Bluetooth/Core Audio may take several seconds to report the final ON state. A diagnostic run timed out immediately before the next state read reported `Active`, which motivated bounded polling windows rather than fixed 500/800 ms sleeps.
- An `Item ID` observed in one cycle is **not a portable/stable identity guarantee**. The reconfigure path treats `Device Name` + `Name` as fallback identity only when the captured ID disappears, then persists the latest observed ID.

These are empirical project observations, not vendor guarantees for all Jabra/Bluetooth headsets.

## PRO X 2 specific evidence

Original 2026-08-07 behavior:

- PRO X 2 on: `GET /battery/<deviceId>/state` returned a battery payload.
- PRO X 2 off: several consecutive queries returned no payload.
- PRO X 2 back on: the payload returned.

Regression observed on 2026-08-31 with G HUB `2026.5.939708`:

- `/devices/list` still found the PRO X 2 and reported `state=ACTIVE` / `resourcesAvailable=true` both ON and OFF;
- `GET /battery/dev00000000/state` returned `NO_SUCH_PATH`;
- known G HUB subscriptions did not restore the removed battery route.

Direct receiver validation on the same PRO X 2 (`VID 046D`, `PID 0AF7`):

- vendor HID collection: UsagePage `0xFFA0`, Usage `0x0001`, 64-byte input/output;
- a Centurion battery request returns a valid `0x51 0x0B ...` frame while connected, with battery percentage at byte 10;
- physical OFF repeatedly produced `51 05 00 FF 03 1A 0B 00 ...`, followed by no valid battery response;
- two complete real AutoSwitch cycles succeeded: OFF selected the configured fallback after two confirmed samples, and ON selected the PRO X 2 again;
- battery values observed in the end-to-end run were 70% and 76%.

Public protocol cross-check: HeadsetControl's Logitech G PRO X 2 LIGHTSPEED implementation:

https://github.com/Sapd/HeadsetControl/blob/master/lib/devices/logitech_gpro_x2_lightspeed.hpp

The project implementation additionally treats the exact OFF signature observed on the tested hardware as a confirmed disconnected observation. Any other missing/invalid response remains `Unknown` and never changes the output.


## Windows Core Audio endpoint APIs

- Microsoft Learn — `IMMDeviceEnumerator::EnumAudioEndpoints`: documents render/capture endpoint enumeration and device-state masks.
  https://learn.microsoft.com/windows/win32/api/mmdeviceapi/nf-mmdeviceapi-immdeviceenumerator-enumaudioendpoints
- Microsoft Learn — Core Audio device properties: documents `PKEY_DeviceInterface_FriendlyName`, `PKEY_Device_DeviceDesc`, `PKEY_Device_FriendlyName`, endpoint IDs and container IDs.
  https://learn.microsoft.com/windows/win32/coreaudio/device-properties
- Microsoft Learn — `IMMDeviceEnumerator::GetDefaultAudioEndpoint`: documents reading the current default endpoint by role.
  https://learn.microsoft.com/windows/win32/api/mmdeviceapi/nf-mmdeviceapi-immdeviceenumerator-getdefaultaudioendpoint

`IPolicyConfig::SetDefaultEndpoint` is an undocumented Windows COM interface. It is intentionally isolated inside the embedded C# bridge and is treated as a compatibility risk, not as a supported Microsoft API.
