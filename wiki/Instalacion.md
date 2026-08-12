# Instalación

## Instalación en un comando

```powershell
powershell.exe -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/Ayerdi/PROX2-AutoSwitch/main/install.ps1 | iex"
```

El bootstrap descarga el ZIP de la última release y su `.sha256`, verifica la integridad, extrae el paquete y lanza el instalador real.

## Manual

1. Descarga el ZIP y `.sha256` desde Releases.
2. Verifica el checksum.
3. Extrae el ZIP completo.
4. Ejecuta:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Install-AutoSwitch.ps1
```

El nombre antiguo `Instalar-PROX2-AutoSwitch.ps1` se conserva por compatibilidad.

[[Installation|Read in English]]
