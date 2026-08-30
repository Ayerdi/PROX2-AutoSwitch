# Audio AutoSwitch

**Stable release: v1.5.0 · Windows 10/11 x64**

Audio AutoSwitch changes the Windows default output automatically when a compatible wireless headset turns on or off, and provides tray controls for switching behavior and Windows Audio Enhancements.

## Start here

- [[Installation]]
- [[How-It-Works]]
- [[Tray-and-Reconfiguration]]
- [[Troubleshooting]]
- [[FAQ]]
- [[Inicio|Español]]

## Detection modes

**WindowsEndpoint** is the general path. It works when Windows exposes a useful connection-state transition for the headset endpoint, such as `Active ↔ Unplugged`.

**Logitech PRO X 2 (v1.5.0)** keeps the backward-compatible `LogitechGHub` config value but now reads the LIGHTSPEED receiver directly through Centurion HID (`046D:0AF7`, UsagePage `0xFFA0`). This restores ON/OFF detection after G HUB 2026.5.939708 stopped exposing the old battery route, and it also provides live battery percentage in the tray.

**LogitechGHub** remains the device-specific fallback for other compatible Logitech headsets such as PRO X / PRO X Wireless when Windows keeps the endpoint `Active` while the physical headset is off.

**SteelSeriesNova5** reads the physical state of an Arctis Nova 5/5X directly over HID, with no SteelSeries GG or third-party software.

An `Unknown` reading never changes the output, and disconnection requires consecutive OFF observations to avoid flapping.

## Resources

- [Repository](https://github.com/Ayerdi/PROX2-AutoSwitch)
- [Website](https://ayerdi.github.io/PROX2-AutoSwitch/)
- [Releases](https://github.com/Ayerdi/PROX2-AutoSwitch/releases)
- [Security](https://github.com/Ayerdi/PROX2-AutoSwitch/security/policy)
