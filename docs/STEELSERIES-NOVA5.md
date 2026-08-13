# SteelSeries Arctis Nova 5 / 5X detection

This provider exists for headsets whose USB audio receiver stays visible to Windows while the physical headset is powered off.

## Upstream protocol evidence

The implementation relies on the open-source HeadsetControl project rather than duplicating its HID protocol inside AutoSwitch:

- HeadsetControl repository: https://github.com/Sapd/HeadsetControl
- Nova 5 implementation: https://github.com/Sapd/HeadsetControl/blob/master/lib/devices/steelseries_arctis_nova_5.hpp
- Shared SteelSeries Nova protocol: https://github.com/Sapd/HeadsetControl/blob/master/lib/devices/protocols/steelseries_protocol.hpp
- Original Nova 5 support PR: https://github.com/Sapd/HeadsetControl/pull/361

Verified on 2026-08-13:

- SteelSeries vendor ID: `0x1038`.
- Nova 5 receiver PID: `0x2232`.
- Nova 5X receiver PID: `0x2253`.
- HeadsetControl's Nova 5 status handling treats connection-status value `0x02` as the headset being offline.
- The CLI's `--timeout` value is expressed in milliseconds.

AutoSwitch requests HeadsetControl battery status in JSON for one exact VID/PID. It maps:

- `BATTERY_AVAILABLE` -> `Connected`
- `BATTERY_CHARGING` -> `Connected`
- Nova-specific `Headset not connected` error -> `Disconnected`
- malformed output, unrelated errors, missing provider or ambiguous devices -> `Unknown`

`Unknown` is fail-safe: AutoSwitch does not change the audio output until a known state returns.

## Pinned Windows provider

The installer uses the portable Windows executable from the official HeadsetControl 4.0.0 release only when the SteelSeries fallback is selected and validated.

```text
Version: 4.0.0
Release date: 2026-07-23
Asset: headsetcontrol-windows-x86_64.exe
SHA256: d78a86cc0f44403d2bcb16294f8f2d91cc2f9f343adb09907a8cef8278309be8
```

The binary is not stored in this repository. The installer verifies the pinned SHA-256 before using the downloaded executable.

## Why not `--connected`?

HeadsetControl currently implements its generic connected check via battery status and returns true only for `BATTERY_AVAILABLE`. A physically connected headset that is charging can report `BATTERY_CHARGING`, so AutoSwitch uses the richer battery JSON instead of that boolean.

## Validation flow

The normal Windows endpoint cycle is always tried first. SteelSeries-specific detection is offered only if Windows fails to reflect ON -> OFF -> ON. The installer then validates a real SteelSeries OFF -> ON cycle before saving `DetectionMode = SteelSeriesNova5`.

The runtime still applies the existing two-reading OFF debounce before switching to the fallback output.
