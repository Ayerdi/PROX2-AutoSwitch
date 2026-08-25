# Resolución de problemas

## No cambia al apagar el auricular

Ejecuta `Verify-AutoSwitch.ps1` y revisa `DetectionMode`. Un auricular genérico necesita que Windows exponga un estado útil del endpoint. Un auricular de la familia Logitech PRO X (PRO X, PRO X 2, PRO X Wireless) necesita G HUB abierto y reconociendo el dispositivo.

## Bluetooth reconecta pero la reconfiguración expira

Windows puede tardar varios segundos en recrear el endpoint. Las versiones actuales usan polling acotado en vez de una lectura instantánea. Reintenta solo cuando Windows vuelva a mostrar el dispositivo.

## Windows seleccionó otro endpoint tras una actualización de controladores

Usa `Reconfigure...`. Los Item ID de Windows son locales al equipo y pueden cambiar; copiar el `config.json` de otra máquina no es compatible.

## G HUB dejó de funcionar tras una actualización

El WebSocket es no oficial y Logitech puede cambiarlo. Revisa primero la última versión y las incidencias del proyecto antes de modificar los tiempos de espera o la seguridad.

## ¿Dónde está el registro?

```text
%LOCALAPPDATA%\PROX2AutoSwitch\autoswitch.log
```

Omite información personal o del dispositivo antes de publicar registros.

[[Troubleshooting|Read in English]]
