# Audio AutoSwitch

**Versión estable: v1.4.0 · Windows 10/11 x64**

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

**LogitechGHub** es la salida alternativa específica para la familia Logitech PRO X (PRO X, PRO X 2, PRO X Wireless), cuyo endpoint de Windows puede seguir en `Active` aunque el auricular esté apagado. AutoSwitch usa el WebSocket local no oficial de G HUB como señal.

**SteelSeriesNova5** lee el estado físico de un Arctis Nova 5/5X directamente por HID, sin SteelSeries GG ni software de terceros.

Un estado `Unknown` nunca cambia la salida y la desconexión necesita lecturas OFF consecutivas para evitar cambios espurios.

## Recursos

- [Repositorio](https://github.com/Ayerdi/PROX2-AutoSwitch)
- [Sitio web](https://ayerdi.github.io/PROX2-AutoSwitch/)
- [Versiones](https://github.com/Ayerdi/PROX2-AutoSwitch/releases)
- [Seguridad](https://github.com/Ayerdi/PROX2-AutoSwitch/security/policy)
