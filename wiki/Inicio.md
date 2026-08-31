# Audio AutoSwitch

**Versión estable: v1.5.0 · Windows 10/11 x64**

Audio AutoSwitch cambia automáticamente la salida predeterminada de Windows cuando un auricular inalámbrico compatible se enciende o apaga, y añade controles desde la bandeja para AutoSwitch y Windows Audio Enhancements.

## Empieza aquí

- [[Instalacion]]
- [[Como-funciona]]
- [[Bandeja-y-reconfiguracion]]
- [[Resolucion-de-problemas]]
- [[FAQ-Espanol]]
- [[Home|English]]

## Modos de detección

**WindowsEndpoint** es el método general: funciona cuando Windows expone un cambio de estado útil, por ejemplo `Active ↔ Unplugged`.

**Logitech PRO X 2 (v1.5.0)** mantiene el valor de configuración compatible `LogitechGHub`, pero ahora lee directamente el receptor LIGHTSPEED mediante Centurion HID (`046D:0AF7`, UsagePage `0xFFA0`). Esto recupera la detección ON/OFF después de que G HUB 2026.5.939708 dejara de exponer la antigua ruta de batería y, además, muestra el porcentaje de batería en la bandeja.

**LogitechGHub** sigue siendo el método alternativo para otros auriculares Logitech compatibles, como PRO X / PRO X Wireless, cuando Windows mantiene el endpoint en `Active` aunque el auricular esté apagado.

**SteelSeriesNova5** lee el estado físico de un Arctis Nova 5/5X directamente por HID, sin SteelSeries GG ni software de terceros.

Un estado `Unknown` nunca cambia la salida y la desconexión necesita lecturas OFF consecutivas para evitar cambios espurios.

## Recursos

- [Repositorio](https://github.com/Ayerdi/PROX2-AutoSwitch)
- [Sitio web](https://ayerdi.github.io/PROX2-AutoSwitch/)
- [Versiones](https://github.com/Ayerdi/PROX2-AutoSwitch/releases)
- [Seguridad](https://github.com/Ayerdi/PROX2-AutoSwitch/security/policy)
