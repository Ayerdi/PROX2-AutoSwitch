# How it works

## WindowsEndpoint

The runtime reads the configured Windows render endpoint with SoundVolumeCommandLine (`svcl.exe`). A typical supported transition is:

```text
Active     → Connected
Unplugged  → Disconnected
```

An invalid export, disabled endpoint or unexpected state is `Unknown`. Unknown never triggers a switch.

## LogitechGHub

For PRO X 2, AutoSwitch connects to the unofficial local G HUB WebSocket on `ws://localhost:9010`, discovers the matching PRO X 2 and uses its battery-state payload as the physical ON/OFF signal.

G HUB device IDs are volatile and are rediscovered; they are not persisted as machine configuration.

## Output switching

The configured Windows Item IDs are passed to `svcl.exe /SetDefault`. Item IDs are machine-local and can change after driver updates or endpoint recreation, so `Reconfigure...` can resolve and persist a fresh ID.

The OFF debounce requires consecutive disconnected readings before moving to the fallback output.

[[Como-funciona|Leer en español]]
