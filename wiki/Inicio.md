# Audio AutoSwitch

**Versión estable: v1.2.4 · Windows 10/11 x64**

Audio AutoSwitch cambia automáticamente la salida predeterminada de Windows cuando un auricular inalámbrico compatible se enciende o apaga, y añade controles desde la bandeja para AutoSwitch y Audio Enhancements.

## Empieza aquí

- [[Instalacion]]
- [[Como-funciona]]
- [[Bandeja-y-reconfiguracion]]
- [[Resolucion-de-problemas]]
- [[FAQ-Espanol]]
- [[Home|English]]

## Modos de detección

**WindowsEndpoint** es el método general: funciona cuando Windows expone un cambio de estado útil, por ejemplo `Active ↔ Unplugged`.

**LogitechGHub** es el fallback específico para Logitech PRO X 2, cuyo endpoint de Windows puede seguir en `Active` aunque el casco esté apagado.

Un estado `Unknown` nunca cambia la salida y la desconexión necesita lecturas OFF consecutivas para evitar cambios espurios.
