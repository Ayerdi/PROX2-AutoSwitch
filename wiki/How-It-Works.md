# How it works

## WindowsEndpoint

The runtime reads the configured Windows render endpoint through the **native Windows Core Audio** APIs (no third-party tools). A typical supported transition is:

```text
Active     → Connected
Unplugged  → Disconnected
```

A disabled endpoint, an unexpected state or a read failure is `Unknown`. Unknown never triggers a switch.

## LogitechGHub

For Logitech wireless headsets (PRO X 2, PRO X Wireless, PRO X and other G HUB-supported headsets), AutoSwitch connects to the unofficial local G HUB WebSocket on `ws://localhost:9010`, discovers the matching headset and uses its battery-state payload as the physical ON/OFF signal.

G HUB device IDs are volatile and are rediscovered; they are not persisted as machine configuration.

## SteelSeriesNova5

For SteelSeries Arctis Nova 5/5X, AutoSwitch reads the headset state directly over HID (native Windows `hid.dll`/`setupapi.dll` calls). No SteelSeries GG or third-party software is required.

## Output switching

The configured Windows Item IDs are set through the native Core Audio COM interface (Console, Multimedia and Communications roles, each verified). Item IDs are machine-local and can change after driver updates or endpoint recreation, so `Reconfigure...` can resolve and persist a fresh ID.

The OFF debounce requires consecutive disconnected readings before moving to the fallback output.

[[Como-funciona|Leer en español]]
