# WindowsEndpointProvider — historical design note

> **Status: SUPERSEDED.** This document records the design path that led to the universal `WindowsEndpoint` mode. The final implementation in v1.2.0 went further: it introduced detection modes, a separate worker process, tray controls, Audio Enhancements support and a universal-first installation wizard. Current behavior is documented in the README, Wiki, CHANGELOG and `AGENT.md`.
>
> **Important correction from later hardware testing:** an early Jabra Evolve 65 test happened to keep the same Item ID through one OFF/ON cycle. Later Bluetooth/Core Audio testing showed that endpoints can be recreated with a different Item ID. Item-ID stability must never be treated as a provider invariant. Current reconfiguration can re-resolve the endpoint by the real `Device Name` + `Name` columns and persist the newly observed ID.

## Why this design existed

The original AutoSwitch detected Logitech PRO X 2 physical state through the unofficial G HUB WebSocket at `ws://localhost:9010`. That worked for PRO X 2 but tied the project to one vendor-specific signal.

A real Jabra Evolve 65 test showed a different and more general pattern: Windows itself changed the render endpoint state when the headset was powered off and back on.

Observed pattern:

```text
headset on   → Active
headset off  → Unplugged
headset on   → Active
```

That evidence suggested a general provider based on the Windows audio endpoint rather than vendor software.

## Proposed provider abstraction

The design separated physical-state detection from the rest of the switching logic:

```text
WindowsEndpointProvider ─┐
                         ├─> Connected / Disconnected / Unknown
LogitechGHubProvider ────┘
                                   │
                                   ▼
                         common OFF debounce
                                   │
                                   ▼
                         svcl /SetDefault
```

The normalized state has three meaningful values:

- `Connected`
- `Disconnected`
- `Unknown`

`Unknown` is deliberately fail-safe: it never causes the runtime to change the Windows output.

## Windows endpoint provider

The provider reads render-device information exported by SoundVolumeCommandLine (`svcl.exe /scomma ""`) and matches the configured endpoint.

Relevant columns:

- `Type`
- `Direction`
- `Device State`
- `Item ID`
- `Device Name`
- `Name`

Only `Type=Device` and `Direction=Render` rows are candidates.

Typical mapping:

```text
Active     → Connected
Unplugged  → Disconnected
anything else / invalid export → Unknown
```

Do not use `/Stdout` before `/GetColumnValue`. An earlier implementation contaminated the returned Item ID with extra item information and broke `/SetDefault`.

If a headset remains `Active` when physically powered off, `WindowsEndpoint` is not a safe detector for that device. The installer must discover that during the real OFF/ON calibration rather than pretending support.

## Logitech G HUB provider

PRO X 2 needs a device-specific fallback because its Windows endpoint can remain `Active` while the physical headset is off.

The fallback uses the unofficial local G HUB interface:

- connect to `ws://localhost:9010`;
- discover PRO X 2 through `/devices/list`;
- use the battery-state response as the ON/OFF signal;
- never persist the volatile G HUB `deviceId`;
- keep hard connect/receive/request/close deadlines.

This interface is reverse-engineered and can change in future G HUB versions.

## Installer calibration

A safe universal installer should not ask the user to understand provider internals.

The intended flow became:

1. select the headset endpoint;
2. select the fallback output;
3. observe the selected headset while ON;
4. ask the user to power it OFF and observe the result;
5. ask the user to power it ON again;
6. choose `WindowsEndpoint` only when Windows demonstrates a reliable state transition;
7. if Windows does not provide a usable signal, offer the G HUB path only when the device is confirmed to be PRO X 2;
8. otherwise abort installation safely.

The final implementation also polls for bounded windows because Bluetooth/Core Audio transitions can take several seconds.

## Shared switching rules

Regardless of provider:

- `Unknown` never switches output;
- consecutive OFF readings are required before treating the headset as disconnected;
- after `/SetDefault`, the current default endpoint should be re-read/verified where practical;
- machine-local Item IDs must not be copied between PCs;
- endpoint recreation must be handled explicitly rather than assuming an ID is permanent.

## Configuration compatibility

The final product uses `DetectionMode` rather than the early draft's provider naming. Existing configurations without the new field are migrated conservatively to the legacy Logitech behavior.

The runtime and installer share pure logic through `lib/AutoSwitchCore.psm1`, which keeps endpoint-state mapping, debounce/config validation and Core Audio helper logic testable with Pester.

## Testing principles that survived into the implementation

Automated tests should cover at least:

- valid `Active` → `Connected` mapping;
- valid `Unplugged`/missing endpoint → `Disconnected` only when the export itself is trustworthy;
- invalid/empty export → `Unknown`;
- OFF debounce;
- identical headset/fallback IDs rejected;
- safe config migration;
- endpoint identity matching based on the separate `Device Name` + `Name` fields;
- timeout behavior for the G HUB path.

Real hardware testing is still required for new headset claims. A unit test can prove parsing and state-machine behavior, but it cannot prove what Windows exposes for a particular wireless device.
