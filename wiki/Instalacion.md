# Instalación

## Instalación en un comando

```powershell
powershell.exe -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/Ayerdi/PROX2-AutoSwitch/main/install.ps1 | iex"
```

El bootstrap descarga el ZIP de la última release y su `.sha256`, verifica el SHA-256, extrae el paquete y lanza el instalador real.

## Instalación manual

1. Descarga el ZIP y `.sha256` desde Releases.
2. Verifica el checksum.
3. Extrae el ZIP completo a una carpeta normal.
4. Ejecuta:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Install-AutoSwitch.ps1
```

El nombre antiguo `Instalar-PROX2-AutoSwitch.ps1` se conserva por compatibilidad.

El asistente enumera los dispositivos de salida, permite elegir el auricular y la salida alternativa, observa un ciclo real OFF/ON y elige el modo de detección: `WindowsEndpoint` cuando Windows ofrece una señal utilizable, `LogitechGHub` para un dispositivo confirmado de la familia Logitech PRO X, o `SteelSeriesNova5` para un receptor Arctis Nova 5/5X.

[[Installation|Read in English]]


## PRO X 2 en v1.5.0

Logitech PRO X 2 LIGHTSPEED usa Centurion HID directo para conocer el estado físico ON/OFF y el porcentaje de batería. El valor de configuración sigue siendo `LogitechGHub` por compatibilidad, pero ya no se usa la ruta eliminada `/battery/<deviceId>/state` de G HUB para detectar el estado del PRO X 2. Una lectura HID desconocida nunca cambia el audio y el apagado sigue necesitando varias observaciones confirmadas.
