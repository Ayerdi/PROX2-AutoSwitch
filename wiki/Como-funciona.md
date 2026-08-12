# Cómo funciona

## WindowsEndpoint

AutoSwitch consulta el endpoint de salida de Windows con `svcl.exe`. Un caso compatible típico pasa de `Active` a `Unplugged` al apagar el auricular.

Estados inválidos o inesperados se tratan como `Unknown` y nunca fuerzan un cambio de salida.

## LogitechGHub

Para PRO X 2, AutoSwitch usa el WebSocket local no oficial de G HUB (`ws://localhost:9010`) para obtener una señal física ON/OFF. El `deviceId` de G HUB se redescubre y no se persiste.

## Cambio de salida

Los Item ID de Windows son locales a cada equipo y pueden cambiar tras drivers o recreación del endpoint. `Reconfigure...` puede resolver el nuevo ID.

[[How-It-Works|Read in English]]
