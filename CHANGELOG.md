# Changelog

Todas las versiones notables de este proyecto se documentan aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.1.0/).
Este proyecto se adhiere a [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-08-07

### Added
- Instalador (`Instalar-PROX2-AutoSwitch.ps1`): descarga de SoundVolumeCommandLine desde NirSoft con verificación SHA-256, calibración de salidas por Item ID real, prueba real de ambos cambios e inicio automático invisible vía `wscript.exe`.
- Runtime (`Runtime-PROX2-AutoSwitch.ps1`): detecta el estado físico del PRO X 2 vía el WebSocket de G HUB (`ws://localhost:9010`) y cambia la salida de audio de Windows.
- Desinstalador (`Desinstalar-PROX2-AutoSwitch.ps1`): elimina proceso, inicio automático y archivos.
- Verificador (`Verificar-PROX2-AutoSwitch.ps1`): diagnóstico rápido.
- Instalador de un clic (`install.ps1`): bootstrap que descarga la última release de GitHub y ejecuta el instalador completo.
- Sitio web (GitHub Pages, `site/`) bilingüe ES/EN.
- Wiki del repositorio completa en ES/EN.
- CI: validación de sintaxis PowerShell, linting con PSScriptAnalyzer y despliegue del sitio a Pages.

### Known limitations
- Solo admite dos salidas (auriculares y alternativa).
- El WebSocket de G HUB no es una API oficial de Logitech; puede cambiar en futuras versiones.
