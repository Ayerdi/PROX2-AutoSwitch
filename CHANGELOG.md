# Changelog

Todas las versiones notables de este proyecto se documentan aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.1.0/).
Este proyecto se adhiere a [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.4] - 2026-08-13

### Added
- Double-click `Install.cmd`, `Verify.cmd`, and `Uninstall.cmd` launchers for users who download the release ZIP.
- Release packaging now also publishes a stable `Audio-AutoSwitch.zip` + SHA-256 alias in addition to the versioned archive.

### Fixed
- Clean installation now polls Bluetooth/Core Audio transitions for 15 s / 15 s / 20 s and refreshes a recreated headset Item ID by `Device Name` + `Name`, matching the hardened Reconfigure flow.
- The verifier no longer reports G HUB as a failure for generic `WindowsEndpoint` installations.
- The one-command bootstrap now uses English/generic Audio AutoSwitch wording.
- Removed leftover one-shot documentation workflows/scripts from `.github/`.
- `Reconfigure...` re-resolves a recreated Bluetooth endpoint using the real `svcl` identity columns **`Device Name` + `Name`**, not the combined display label. This fixes the edge case where a headset returns after power-on with a different `Item ID`, while avoiding collisions between multiple render endpoints belonging to the same device. Regression tests cover exact identity matching.

### Changed
- README, GitHub Pages, maintainer notes, security/source notes and the historical WindowsEndpoint design document were refreshed to match the post-v1.2.3 behavior and hardware findings.

## [1.2.3] - 2026-08-12

### Fixed
- **`Reconfigure...` tolera la latencia real de headsets Bluetooth**: el wizard hace polling cada 500 ms y usa ventanas de hasta 15 s para el primer ON y el OFF, y hasta 20 s para el ON final. Esto evita falsos negativos cuando Windows tarda varios segundos en reflejar `Active`/`Unplugged`.
- **Los headsets Bluetooth pueden reaparecer con un `Item ID` distinto** tras apagarse y reconectarse. Si el ID original ya no aparece, Reconfigure vuelve a localizar el endpoint por su nombre estable, usa el estado observado y persiste el `Item ID` más reciente en `config.json`. Validado en hardware real con Jabra Evolve 65 (`ON → OFF → ON`, reinicio y nuevo `OFF → ON`).
- Se añadió diagnóstico detallado cuando un estado no llega a tiempo: el log muestra el estado final y los endpoints/IDs que `svcl` está viendo, para distinguir timing de un endpoint recreado.
- `Invoke-Reconfigure` envuelve también la apertura/construcción del diálogo en `try/catch`, de modo que los fallos previos a `Detect mode...` quedan registrados en `autoswitch.log`.

## [1.2.2] - 2026-08-12

### Fixed
- **Reconfigure endurecido al cambiar entre `WindowsEndpoint` y `LogitechGHub`**: una config de `WindowsEndpoint` podía no tener `GHubPort`; al reconfigurar a un PRO X 2, `Connect-GHub` usa ahora el puerto seguro por defecto (9010) en vez de fallar por una propiedad ausente.
- Los campos opcionales de config (`DetectionMode`, `EnhancementsDeviceId`, `GHubDisplayName`, `GHubPort`) se gestionan con `Add-Member -Force` (crea o actualiza) y se **eliminan los campos G HUB obsoletos** al pasar a `WindowsEndpoint`, para no dejar asociaciones fantasma.
- **Varios PRO X 2 en G HUB**: el wizard ya no adivina cuál corresponde; pregunta al usuario (Sí/No/Cancelar) por cada candidato hasta confirmar uno, o cancela y deja la config intacta.

## [1.2.1] - 2026-08-12

### Fixed
- **`Reconfigure...` del tray ahora ejecuta el wizard completo de detección** en vez de solo intercambiar `HeadsetId`/`SpeakerId`. La versión anterior dejaba el `DetectionMode` y la asociación G HUB antiguos, lo que producía dos estados rotos: un PRO X 2 reconfigurado a Jabra seguía vigilando el PRO X 2, y un Jabra reconfigurado a PRO X 2 seguía en `WindowsEndpoint` (Windows siempre reporta el endpoint del PRO X 2 `Active`, así que el apagado nunca se detectaba). Ahora valida el ciclo `ON → OFF → ON`, determina `WindowsEndpoint` o `LogitechGHub` (con confirmación del PRO X 2 vía G HUB), y actualiza `DetectionMode`, `GHubDisplayName` y `EnhancementsDeviceId`. Si no hay método compatible, deja la config intacta.
- **README dentro del ZIP/tag desfasado**: la v1.2.0 incluyó un README que describía el flujo "G HUB primero" del instalador; el flujo real es universal-first. Corregido en el repo y en esta release.

## [1.2.0] - 2026-08-12

### Added
- Modo universal `WindowsEndpoint`: detecta el estado físico del auricular leyendo el estado del endpoint de audio de Windows (`svcl /scomma`, columna `Device State`). Funciona con cualquier auricular inalámbrico cuyo endpoint refleje el estado físico (p. ej. Jabra Evolve 65: `Active` → conectado, `Unplugged`/ausente → desconectado).
- Campo `DetectionMode` en config (`WindowsEndpoint` | `LogitechGHub`). Compatibilidad hacia atrás: una config sin `DetectionMode` se interpreta como `LogitechGHub` y se migra a v1.2.0 automáticamente en el primer arranque.
- Icono de bandeja (tray) en el runtime con icono propio (`assets/icon.ico`): activar/desactivar AutoSwitch, deshabilitar/habilitar Audio Enhancements del headset configurado y salir. El menú de enhancements se refresca cada 5 s para reflejar el estado real (`SysFx`).
- Menú de bandeja con **líneas de información** (Headset / Fallback / Next switch, refrescadas cada 5 s) y opción **Reconfigure...** que abre un diálogo para elegir un nuevo auricular/fallback de los dispositivos actuales de Windows sin reinstalar; guarda `config.json` y el worker recarga la config en el siguiente ciclo (flag `control/reload.flag`).
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
