# Tray and reconfiguration

The tray menu shows the configured headset, fallback output and expected next switch.

Actions:

- enable/disable automatic switching without exiting;
- disable/enable Windows Audio Enhancements for the configured headset (UAC only for the elevated helper);
- `Reconfigure...` to select current devices and validate a fresh ON → OFF → ON cycle;
- exit AutoSwitch.

Reconfiguration polls for real Bluetooth timing and can refresh a recreated endpoint's Item ID using its stable Windows identity.

![Real AutoSwitch tray menu](https://raw.githubusercontent.com/Ayerdi/PROX2-AutoSwitch/main/site/assets/tray-menu.png)

[[Bandeja-y-reconfiguracion|Leer en español]]


## PRO X 2 in v1.5.0

Logitech PRO X 2 LIGHTSPEED uses direct Centurion HID for physical ON/OFF state and battery percentage. The configuration value remains `LogitechGHub` for backward compatibility, but G HUB's removed `/battery/<deviceId>/state` route is not used for PRO X 2 state detection anymore. Unknown HID reads never switch audio, and OFF still requires consecutive confirmed observations.
