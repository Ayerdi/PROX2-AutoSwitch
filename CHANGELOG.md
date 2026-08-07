# Changelog

Todas las versiones notables de este proyecto se documentan aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.1.0/).
Este proyecto se adhiere a [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] — hardening

### Added
- Timeouts acotados en el WebSocket de G HUB: conexión (5 s), espera de respuesta (5 s) y límite global por petición (10 s). Tras un timeout se cierra el socket, se registra en el log y se reintenta; mientras el estado sea desconocido no se cambia la salida de audio.
- `lib/AutoSwitchCore.psm1`: módulo de lógica pura compartida (extracción de Item ID, debounce OFF, validación de config) usada por instalador, runtime y tests.
- Tests Pester (`tests/`) ejecutados en CI: extracción de Item ID válido, rechazo de salida inválida, regresión `/Stdout`, debounce OFF tras `OffMissThreshold`, payload único que no dispara OFF, rechazo de IDs idénticos.
- `install.ps1` verifica SHA-256 del ZIP de la release contra un asset `.sha256` publicado antes de extraer/ejecutar. Selección determinista: exactamente un `PROX2-AutoSwitch-*.zip`, fallo si hay cero o varios.
- Workflow de release (`.github/workflows/release.yml`): genera el ZIP + `.sha256` automáticamente en tags `v*`.
- Desinstalador reporta cada paso (proceso, inicio automático, directorio) y distingue éxito completo, limpieza parcial fallida y "nada que desinstalar".

### Changed
- Configuración de instalación ahora incluye `ConnectTimeoutMs`, `ReceiveTimeoutMs`, `RequestTimeoutMs` (config v1.1.0).

### Fixed
- `install.ps1`: eliminada la comprobación engañosa de `$LASTEXITCODE` tras invocar el instalador `.ps1`; los errores se propagan por excepción.
- Desinstalador: frontera de ruta en la detección de "ejecutándose desde InstallDir" (`$InstallDir\*`).
- Verificador: lee `GHubPort` de config en lugar de hardcodear 9010.

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
