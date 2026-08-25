# Troubleshooting

## It never switches when the headset powers off

Run `Verify-AutoSwitch.ps1` and check the configured `DetectionMode`. A generic headset requires Windows to expose a useful endpoint state. A Logitech PRO X family headset (PRO X, PRO X 2, PRO X Wireless) requires G HUB to be running and recognizing the device.

## Bluetooth reconnects but reconfiguration times out

Bluetooth endpoint recreation can take several seconds. Current releases use bounded polling windows rather than one instantaneous state read. Retry only after Windows itself shows the device again.

## Windows selected a different endpoint after a driver update

Run `Reconfigure...`. Windows Item IDs are machine-local and can change; copying another machine's `config.json` is unsupported.

## G HUB stopped working after an update

The local WebSocket is unofficial. Check the latest project release/issues before changing timeout or safety behavior.

## Where is the log?

```text
%LOCALAPPDATA%\PROX2AutoSwitch\autoswitch.log
```

Redact personal/device information before posting logs publicly.

[[Resolucion-de-problemas|Leer en español]]
