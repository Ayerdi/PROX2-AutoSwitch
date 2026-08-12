# Changelog

Todas las versiones notables de este proyecto se documentan aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.1.0/).
Este proyecto se adhiere a [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-08-12

### Added
- Modo universal `WindowsEndpoint`: detecta el estado físico del auricular leyendo el estado del endpoint de audio de Windows (`svcl /scomma`, columna `Device State`). Funciona con cualquier auricular inalámbrico cuyo endpoint refleje el estado físico (p. ej. Jabra Evolve 65: `Active` → conectado, `Unplugged`/ausente → desconectado).
- Campo `DetectionMode` en config (`WindowsEndpoint` | `LogitechGHub`). Compatibilidad hacia atrás: una config sin `DetectionMode` se interpreta como `LogitechGHub` y se migra a v1.2.0 automáticamente en el primer arranque.
- Icono de bandeja (tray) en el runtime con icono propio (`assets/icon.ico`): activar/desactivar AutoSwitch, deshabilitar/habilitar Audio Enhancements del headset configurado y salir. El menú de enhancements se refresca cada 5 s para reflejar el estado real (`SysFx`).
- Arquitectura de runtime a dos procesos: el polling corre en un **proceso worker separado** (`AUTOSWITCH_WORKER=1`, mismo script re-ejecutado, con guard anti-polls-concurrentes) para que el message pump de WinForms (`Application.Run()` sobre un `Form` invisible) y la bandeja nunca se bloqueen. La comunicación es por flags de control (`control/enabled.flag`, `control/stop.flag`).
- `Toggle-AudioEnhancements.ps1`: helper elevado (UAC puntual) que escribe `PKEY_AudioEndpoint_Disable_SysFx` en el endpoint del headset vía `IPolicyConfig`, verifica el resultado y actualiza el menú solo si el cambio se confirmó. El runtime nunca se ejecuta elevado.
- Instalador universal: selecciona headset y fallback desde la lista de dispositivos de Windows y auto-detecta el modo (si Windows refleja `Active ↔ Unplugged` → `WindowsEndpoint`; si no y es Logitech con G HUB → `LogitechGHub`; si no hay método compatible, aborta). G HUB filtra solo candidatos `PRO X 2` (evita seleccionar un ratón/teclado por accidente). El instalador ya **no vuelve a descargar `svcl.exe`** si ya está instalado.
- `DisableEnhancementsOnStart` y `EnhancementsDeviceId` opcionales en config; el instalador ofrece deshabilitar enhancements del headset tras instalar.
- Toda la interop COM (crear objetos, castear a interfaces, leer/escribir el FxStore) vive ahora en **C# compilado con `Add-Type`**, donde el cast a las interfaces `[ComImport]` (`IPolicyConfig`, `IMMDeviceEnumerator`, `IMMDevice`, `IPropertyStore`) es nativo — en PowerShell 5.1 el cast de un RCW COM a una interfaz custom falla.
- Tests Pester nuevos: fixture real de exportación `svcl /scomma` (`tests/fixtures/svcl-export.csv` con `Name`/`Device Name` separados), filtrado `Type=Device` + `Direction=Render`, `Get-SvclDeviceLabel` (`Device Name — Name`), `Test-SvclExportValid` (exige `Item ID` + `Device State`), y estados `Active→Connected` / `Unplugged→Disconnected` / `Unknown`.
- Todo el texto visible (instalador, runtime, helper, verificador, desinstalador) ahora está en inglés.

### Changed
- Config v1.2.0 con `DetectionMode` (el runtime conserva el comportamiento G HUB para instalaciones existentes).
- `Runtime-PROX2-AutoSwitch.ps1`: lanza el worker con `$PSCommandPath` (no `$MyInvocation.MyCommand.Path`, que podía quedar vacío dentro de funciones en PS 5.1).
- El runtime espera `Toggle-AudioEnhancements.ps1` y `icon.ico` en el directorio de instalación; el instalador los copia.
- Verificador muestra `DetectionMode`, estado del endpoint del headset y estado de enhancements.
- En el modo `LogitechGHub`, la conexión a G HUB es **persistente**: se conecta una vez, resuelve el `deviceId` una vez, y solo reconecta (re-resolviendo el `deviceId`, que puede cambiar tras una reconexión) ante un fallo.
- Los scripts con caracteres no-ASCII llevan **BOM UTF-8** (lo exige PSScriptAnalyzer).

### Fixed
- El estado `Unknown` (svcl falla, `Disabled`, valor raro o **export inválido/vacío**) nunca cambia la salida de audio: protege de mandar al fallback por un fallo puntual de svcl. Solo un export válido + fila ausente se considera `Disconnected`.
- `Get-EndpointFxState` lee ahora `PKEY_AudioEndpoint_Disable_SysFx` del **FxStore** vía `IPolicyConfig::GetPropertyValue(deviceId, bFxStore=true)` — el mismo store donde el helper elevado escribe. Antes lo leía del `IPropertyStore` del endpoint (donde la clave no existe) y el menú del tray siempre ofrecía "Disable" aunque ya estuvieran deshabilitados.
- `Add-Type` con sentinel correcto (`AutoSwitch.EndpointFx`): el primer intento usaba un nombre que no existía y reintentaba compilar en cada llamada, fallando en la segunda.
- `Get-SvclRenderDevice` devuelve ahora el array correctamente (un `return ,$array` envolvía el resultado y rompía `.Count` en los tests) y usa `Get-CsvColumn` para acceso fiable a propiedades.
- Instalador: eliminadas funciones huérfanas que quedaron sin uso tras el rediseño del flujo de selección.
- El icono de bandeja usa un `.ico` propio en vez de `SystemIcons::Application` (que no era legible/identificable).

### Security
- El WebSocket de G HUB (`ws://localhost:9010`) no es una API oficial de Logitech; puede cambiar en futuras versiones. Ver `AGENT.md`/`SOURCES.md`.

## [1.1.0] - 2026-08-07

### Added
- Timeouts acotados en el WebSocket de G HUB: conexión (5 s), espera de respuesta (5 s) y límite global por petición (10 s). Tras un timeout se cierra el socket, se registra en el log y se reintenta; mientras el estado sea desconocido no se cambia la salida de audio.
- Cierre del WebSocket con límite duro: `CloseAsync` espera como máximo 1 s y, si falla o expira, `Abort()` + `Dispose()` garantizan que la recuperación nunca se quede colgada con un G HUB atascado. Aplicado también a la comprobación de G HUB del instalador.
- `lib/AutoSwitchCore.psm1`: módulo de lógica pura compartida (extracción de Item ID, debounce OFF, validación de config, token de timeout) usada por instalador, runtime y tests.
- Tests Pester (`tests/`) ejecutados en CI: extracción de Item ID válido, rechazo de salida inválida, regresión `/Stdout`, debounce OFF tras `OffMissThreshold`, payload único que no dispara OFF, rechazo de IDs idénticos y autocancelación del token de timeout.
- `install.ps1` verifica SHA-256 del ZIP de la release contra un asset `.sha256` publicado antes de extraer/ejecutar. Selección determinista: exactamente un `PROX2-AutoSwitch-*.zip`, fallo si hay cero o varios. Todo el flujo (descarga, checksum, extracción, ejecución) está dentro de un `try/finally` que limpia `%TEMP%` en cualquier fallo.
- Workflow de release (`.github/workflows/release.yml`): genera el ZIP + `.sha256` automáticamente en tags `v*`.
- Desinstalador reporta cada paso (proceso, inicio automático, directorio) y distingue éxito completo, limpieza parcial fallida y "nada que desinstalar". La eliminación programada vía `cmd.exe` se marca solo si se lanza correctamente.

### Changed
- Configuración de instalación ahora incluye `ConnectTimeoutMs`, `ReceiveTimeoutMs`, `RequestTimeoutMs` (config v1.1.0).
- Instalador de un clic (`install.ps1`): solo instala releases que publiquen checksum `.sha256`; documenta la verificación antes de extraer.

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
