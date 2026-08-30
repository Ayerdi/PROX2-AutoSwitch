# Cómo funciona

## WindowsEndpoint

AutoSwitch consulta el endpoint de salida de Windows mediante las **APIs nativas de Core Audio** de Windows (sin herramientas de terceros). Un caso compatible típico pasa de `Active` a `Unplugged` al apagar el auricular.

Estados inválidos o inesperados se tratan como `Unknown` y nunca fuerzan un cambio de salida.

## LogitechGHub

Para auriculares Logitech inalámbricos (PRO X 2, PRO X Wireless, PRO X y otros soportados por G HUB), AutoSwitch usa el WebSocket local no oficial de G HUB (`ws://localhost:9010`) para obtener una señal física ON/OFF. El `deviceId` de G HUB se redescubre y no se persiste.

## SteelSeriesNova5

Para SteelSeries Arctis Nova 5/5X, AutoSwitch lee el estado del auricular directamente por HID (llamadas nativas a `hid.dll`/`setupapi.dll` de Windows). No requiere SteelSeries GG ni software de terceros.

## Cambio de salida

Los Item ID de Windows se establecen mediante la interfaz COM nativa de Core Audio (roles Console, Multimedia y Communications, cada uno verificado). Son locales a cada equipo y pueden cambiar tras actualizaciones de controladores o la recreación del endpoint. `Reconfigure...` puede resolver y persistir el nuevo ID.

El debounce de apagado exige varias lecturas consecutivas de desconexión antes de pasar a la salida alternativa.

[[How-It-Works|Read in English]]


## PRO X 2 en v1.5.0

Logitech PRO X 2 LIGHTSPEED usa Centurion HID directo para conocer el estado físico ON/OFF y el porcentaje de batería. El valor de configuración sigue siendo `LogitechGHub` por compatibilidad, pero ya no se usa la ruta eliminada `/battery/<deviceId>/state` de G HUB para detectar el estado del PRO X 2. Una lectura HID desconocida nunca cambia el audio y el apagado sigue necesitando varias observaciones confirmadas.
