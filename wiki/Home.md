# Audio AutoSwitch

**Stable release: v1.2.5 · Windows 10/11 x64**

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

**LogitechGHub** is the device-specific fallback for Logitech PRO X 2, whose Windows endpoint can remain `Active` while the physical headset is off. AutoSwitch uses G HUB's unofficial local WebSocket as the signal.

An `Unknown` reading never changes the output, and disconnection requires consecutive OFF observations to avoid flapping.

## Resources

- [Repository](https://github.com/Ayerdi/PROX2-AutoSwitch)
- [Website](https://ayerdi.github.io/PROX2-AutoSwitch/)
- [Releases](https://github.com/Ayerdi/PROX2-AutoSwitch/releases)
- [Security](https://github.com/Ayerdi/PROX2-AutoSwitch/security/policy)
