# Resolución de problemas

## No cambia al apagar el auricular

Ejecuta `Verify-AutoSwitch.ps1` y revisa `DetectionMode`. Un auricular genérico necesita que Windows exponga un cambio de estado útil. PRO X 2 necesita G HUB abierto y reconociendo el dispositivo.

## Bluetooth tarda al reconectar

Windows puede tardar varios segundos en recrear el endpoint. Las versiones actuales usan polling acotado en vez de una lectura instantánea.

## Cambió el endpoint tras actualizar drivers

Usa `Reconfigure...`. Los Item ID son locales al equipo y pueden cambiar.

## G HUB dejó de funcionar tras una actualización

El WebSocket es no oficial y Logitech puede cambiarlo. Revisa primero la última release/issues del proyecto.

[[Troubleshooting|Read in English]]
