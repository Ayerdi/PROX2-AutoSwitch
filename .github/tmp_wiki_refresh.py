from pathlib import Path

ROOT = Path('/tmp/wiki')

pages = {
'Home.md': r'''# Audio AutoSwitch — Wiki

Audio AutoSwitch automatically changes the Windows default audio output when a supported wireless headset connects or disconnects.

It supports two detection paths:

- **WindowsEndpoint** — generic mode for headsets whose Windows render endpoint reflects the physical state (`Active` ↔ `Unplugged`/absent). Validated with a **Jabra Evolve 65**.
- **LogitechGHub** — fallback for the **Logitech PRO X 2 LIGHTSPEED**, whose endpoint remains visible to Windows while the physical headset is off.

## Current versions

- **Latest stable:** [v1.2.3](https://github.com/Ayerdi/PROX2-AutoSwitch/releases/tag/v1.2.3)
- **Current main:** includes additional **Unreleased** hardening for Bluetooth endpoints that are recreated with a different Windows `Item ID`.

The stable v1.2.3 added bounded polling to `Reconfigure...`, detailed endpoint diagnostics and persistence of the latest observed Bluetooth endpoint ID. Current `main` further hardens the recreated-ID fallback by matching the real `svcl` identity columns `Device Name` + `Name`.

## What you can do from the tray

- See the configured headset and fallback output.
- Pause/resume AutoSwitch.
- **Reconfigure...** without reinstalling: choose another headset/fallback and re-detect `WindowsEndpoint` or `LogitechGHub`.
- Enable/disable Windows Audio Enhancements for the configured headset (one-off UAC elevation).
- Exit AutoSwitch.

## Documentation

### Español

- [[Guía de instalación|Guia-Instalacion-ES]]
- [[Verificar funcionamiento|Verificar-ES]]
- [[Preguntas frecuentes|FAQ-ES]]
- [[Seguridad|Seguridad-ES]]
- [[Desinstalar|Desinstalar-ES]]

### English

- [[Install guide|Install-Guide-EN]]
- [[Verify operation|Verify-EN]]
- [[FAQ|FAQ-EN]]
- [[Security|Security-EN]]
- [[Uninstall|Uninstall-EN]]

## Important model

Windows audio `Item ID`s are **machine-local identifiers**, not portable configuration. They can change after reinstalling Windows/drivers or when Windows recreates a Bluetooth endpoint. Do not copy `config.json` between PCs.

The G HUB `deviceId` is also volatile and is never persisted; the runtime resolves the current PRO X 2 by its display name.

Project page: https://ayerdi.github.io/PROX2-AutoSwitch/
''',

'_Sidebar.md': r'''## Audio AutoSwitch

**Español**
- [[Inicio|Home]]
- [[Instalación|Guia-Instalacion-ES]]
- [[Verificar|Verificar-ES]]
- [[FAQ|FAQ-ES]]
- [[Seguridad|Seguridad-ES]]
- [[Desinstalar|Desinstalar-ES]]

**English**
- [[Home|Home]]
- [[Install|Install-Guide-EN]]
- [[Verify|Verify-EN]]
- [[FAQ|FAQ-EN]]
- [[Security|Security-EN]]
- [[Uninstall|Uninstall-EN]]

---
[Latest release](https://github.com/Ayerdi/PROX2-AutoSwitch/releases/latest) · [Project page](https://ayerdi.github.io/PROX2-AutoSwitch/)
''',

'Guia-Instalacion-ES.md': r'''# Guía de instalación — Español

## Requisitos

- Windows 10/11 x64.
- PowerShell 5.1 o superior.
- Internet durante la instalación para obtener SoundVolumeCommandLine de NirSoft si todavía no está instalado.
- Para **PRO X 2 / LogitechGHub**: Logitech G HUB instalado, abierto y reconociendo el auricular.
- No hacen falta permisos de administrador para el funcionamiento normal. El cambio de Audio Enhancements sí muestra UAC.

## Instalación en un clic

Abre PowerShell y ejecuta:

```powershell
powershell.exe -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/Ayerdi/PROX2-AutoSwitch/main/install.ps1 | iex"
```

El bootstrap:

1. Consulta la última release estable de GitHub.
2. Descarga exactamente un ZIP y su `.sha256`.
3. Verifica SHA-256 **antes** de extraer/ejecutar.
4. Ejecuta el instalador completo.
5. Limpia los temporales incluso si algo falla.

## Asistente de instalación

El instalador lista únicamente endpoints de salida reales (`Type=Device`, `Direction=Render`).

1. Elige **HEADSET**.
2. Elige **FALLBACK** (por ejemplo, altavoces).
3. Mantén el auricular encendido y sigue la prueba `ON → OFF → ON`.
4. Si Windows refleja `Active ↔ Unplugged/ausente`, se configura `WindowsEndpoint`.
5. Si Windows no refleja el apagado y confirmas que es un PRO X 2, el instalador intenta `LogitechGHub`.
6. Se prueban de verdad ambos cambios de salida antes de terminar.
7. Opcionalmente puedes deshabilitar Audio Enhancements del headset.

Si no se puede demostrar un método de detección compatible, **no instala una configuración dudosa**.

## Reconfigure... después de instalar

Desde el icono de bandeja puedes cambiar headset/fallback sin reinstalar.

El wizard vuelve a validar `ON → OFF → ON`. Bluetooth/Core Audio puede tardar varios segundos, por lo que las esperas son acotadas pero amplias. La release v1.2.3 introdujo polling y diagnóstico detallado; `main` añade hardening para reencontrar un endpoint Bluetooth recreado mediante sus columnas reales `Device Name` + `Name` y guardar el `Item ID` más reciente.

Si Reconfigure no puede demostrar un modo compatible, deja la configuración anterior intacta.

## Dónde se instala

```text
%LOCALAPPDATA%\PROX2AutoSwitch\
```

Ahí encontrarás, entre otros:

- `PROX2AutoSwitch.ps1`
- `config.json`
- `svcl.exe`
- `autoswitch.log`
- `Toggle-AudioEnhancements.ps1`
- `lib\AutoSwitchCore.psm1`

El inicio automático usa un acceso directo que lanza `wscript.exe`, para evitar una ventana de PowerShell visible.

## Importante sobre Item ID

No copies `config.json` de otro PC. Los `Item ID` de audio pertenecen al Windows actual y pueden cambiar tras drivers, reinstalación o recreación de endpoints Bluetooth.

Siguiente paso: [[Verificar funcionamiento|Verificar-ES]].
''',

'Install-Guide-EN.md': r'''# Install guide — English

## Requirements

- Windows 10/11 x64.
- PowerShell 5.1 or newer.
- Internet during installation so NirSoft SoundVolumeCommandLine can be downloaded if not already installed.
- For **PRO X 2 / LogitechGHub**: Logitech G HUB installed, open and recognizing the headset.
- Normal runtime does not require administrator rights. The Audio Enhancements toggle uses one-off UAC elevation.

## One-click install

Open PowerShell and run:

```powershell
powershell.exe -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/Ayerdi/PROX2-AutoSwitch/main/install.ps1 | iex"
```

The bootstrap:

1. Resolves the latest stable GitHub release.
2. Downloads exactly one release ZIP and its `.sha256` asset.
3. Verifies SHA-256 **before** extraction/execution.
4. Runs the full installer.
5. Cleans temporary files even on failure.

## Setup wizard

The installer lists real render endpoints only (`Type=Device`, `Direction=Render`).

1. Pick the **HEADSET**.
2. Pick the **FALLBACK** output (for example speakers).
3. Keep the headset on and follow the `ON → OFF → ON` test.
4. If Windows reflects `Active ↔ Unplugged/absent`, it configures `WindowsEndpoint`.
5. If Windows cannot see the physical power-off and you confirm a PRO X 2, it tries `LogitechGHub`.
6. It actually tests both output switches before finishing.
7. You can optionally disable Audio Enhancements for the headset.

If no compatible detection method can be proven, the installer **does not create a questionable setup**.

## Reconfigure... after installation

Use the tray icon to change headset/fallback without reinstalling.

The wizard validates `ON → OFF → ON` again. Bluetooth/Core Audio can take several seconds, so waits are bounded but intentionally generous. Stable v1.2.3 added polling and detailed endpoint diagnostics; current `main` additionally hardens recreated Bluetooth endpoints by resolving the real `Device Name` + `Name` columns and persisting the newest `Item ID`.

If Reconfigure cannot prove a compatible detection mode, the previous configuration is left untouched.

## Install location

```text
%LOCALAPPDATA%\PROX2AutoSwitch\
```

Important files include:

- `PROX2AutoSwitch.ps1`
- `config.json`
- `svcl.exe`
- `autoswitch.log`
- `Toggle-AudioEnhancements.ps1`
- `lib\AutoSwitchCore.psm1`

Autostart uses a shortcut that launches `wscript.exe` so no PowerShell console remains visible.

## Item ID warning

Do not copy `config.json` from another PC. Windows audio `Item ID`s belong to the current machine and can change after drivers, reinstallations or Bluetooth endpoint recreation.

Next: [[Verify operation|Verify-EN]].
''',

'Verificar-ES.md': r'''# Verificar funcionamiento — Español

## Diagnóstico automático

Desde la carpeta extraída de la release o usando el script instalado:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\PROX2AutoSwitch\Verificar-PROX2-AutoSwitch.ps1"
```

Comprueba la configuración, el modo de detección, los endpoints y el estado de Audio Enhancements.

## Prueba manual normal

1. Enciende/conecta el headset.
2. Espera unos segundos. Algunos Bluetooth tardan más después de reconectar.
3. Windows debe seleccionar el headset.
4. Apágalo/desconéctalo.
5. Cuando Windows refleje la desconexión y dos comprobaciones consecutivas la confirmen, debe cambiar al fallback.
6. Vuelve a encenderlo y verifica que regresa al headset.

El runtime exige dos lecturas OFF consecutivas para evitar cambios por una lectura puntual incorrecta.

## Prueba de Reconfigure

Después de cambiar headset o modo desde **Reconfigure...**:

1. Completa el ciclo `ON → OFF → ON` del wizard.
2. Comprueba que el menú muestra el headset/fallback nuevos.
3. Haz `OFF → ON` una vez más en uso normal.
4. Pulsa **Exit**, vuelve a iniciar AutoSwitch y repite `OFF → ON`.
5. Revisa `config.json`: el `DetectionMode` debe ser coherente (`WindowsEndpoint` o `LogitechGHub`).

Este flujo se validó físicamente con **PRO X 2 → Jabra Evolve 65**, recarga del worker, reinicio y nuevo OFF/ON.

## Log en vivo

```powershell
Get-Content "$env:LOCALAPPDATA\PROX2AutoSwitch\autoswitch.log" -Wait -Tail 40
```

Entradas útiles:

```text
Reconfigure wizard: ON=Connected OFF=Disconnected ON=Connected (...)
Reconfigured: headset=... fallback=... mode=WindowsEndpoint
Config reloaded (reconfigure).
Output changed -> ...
```

Si hay timeout, el diagnóstico moderno registra el último estado y los endpoints/IDs visibles en `svcl`.

## Si no cambia de salida

- Confirma que AutoSwitch está **Enabled** en la bandeja.
- `WindowsEndpoint`: comprueba que Windows realmente cambia `Active ↔ Unplugged/ausente`.
- PRO X 2: confirma que G HUB está abierto y reconoce el auricular.
- Ejecuta `Reconfigure...` si Windows ha recreado/cambiado el endpoint.
- No edites GUIDs a mano salvo diagnóstico avanzado.
''',

'Verify-EN.md': r'''# Verify operation — English

## Automatic diagnostics

Run the installed verifier:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\PROX2AutoSwitch\Verificar-PROX2-AutoSwitch.ps1"
```

It checks configuration, detection mode, endpoints and Audio Enhancements state.

## Normal manual test

1. Power on/connect the headset.
2. Wait a few seconds. Some Bluetooth devices take longer after reconnecting.
3. Windows should select the headset.
4. Power it off/disconnect it.
5. Once Windows reflects disconnect and two consecutive runtime checks confirm it, Windows should select the fallback.
6. Power it on again and verify the headset is selected again.

The runtime requires two consecutive OFF readings to avoid switching on a one-off bad reading.

## Reconfigure test

After changing headset/mode through **Reconfigure...**:

1. Complete the wizard's `ON → OFF → ON` cycle.
2. Confirm the tray shows the new headset/fallback.
3. Perform another normal `OFF → ON` cycle.
4. Choose **Exit**, start AutoSwitch again and repeat `OFF → ON`.
5. Inspect `config.json`: `DetectionMode` should match the selected path (`WindowsEndpoint` or `LogitechGHub`).

This exact flow was hardware-validated with **PRO X 2 → Jabra Evolve 65**, worker config reload, process restart and another OFF/ON cycle.

## Live log

```powershell
Get-Content "$env:LOCALAPPDATA\PROX2AutoSwitch\autoswitch.log" -Wait -Tail 40
```

Useful entries:

```text
Reconfigure wizard: ON=Connected OFF=Disconnected ON=Connected (...)
Reconfigured: headset=... fallback=... mode=WindowsEndpoint
Config reloaded (reconfigure).
Output changed -> ...
```

On timeout, current diagnostics log the last observed state and the endpoints/IDs visible in `svcl`.

## If switching does not happen

- Confirm AutoSwitch is **Enabled** in the tray.
- `WindowsEndpoint`: verify Windows really exposes `Active ↔ Unplugged/absent`.
- PRO X 2: verify G HUB is open and recognizes the headset.
- Run `Reconfigure...` if Windows recreated/changed the endpoint.
- Do not hand-edit GUIDs except for advanced diagnostics.
''',

'FAQ-ES.md': r'''# Preguntas frecuentes — Español

## ¿Funciona solo con Logitech PRO X 2?

No. Desde v1.2.0 existe `WindowsEndpoint`, que funciona con auriculares cuyo endpoint de salida de Windows refleja el estado físico. Se validó con un **Jabra Evolve 65** (`Active` al conectar, `Unplugged` al apagar).

El PRO X 2 usa el fallback `LogitechGHub` porque Windows mantiene su endpoint visible incluso cuando el auricular físico está apagado.

## ¿Es universal para cualquier auricular inalámbrico?

No se promete eso. Es compatible cuando:

- Windows expone un cambio de estado útil, o
- existe un provider específico soportado (actualmente PRO X 2 vía G HUB).

Si el wizard no puede demostrar un método compatible, no inventa uno.

## ¿Por qué Reconfigure tarda varios segundos?

Bluetooth/Core Audio puede tardar en reflejar `Active`/`Unplugged`, especialmente al volver a encender un dispositivo. El wizard usa polling con timeouts acotados en vez de una única lectura rápida.

## ¿Puede cambiar el Item ID de mi auricular?

Sí. Es un identificador local de Windows y no debe considerarse permanente. Puede cambiar tras drivers, reinstalación o recreación del endpoint Bluetooth.

La v1.2.3 ya guarda el último ID observado durante Reconfigure. `main` añade hardening adicional: si desaparece el ID capturado, re-resuelve el endpoint Render por las columnas reales `Device Name` + `Name`, evitando confundir dos salidas del mismo dispositivo.

## ¿Puedo copiar config.json a otro PC?

No. Contiene IDs de endpoints del equipo actual.

## ¿Necesita administrador?

No para el runtime ni para cambiar salidas. El toggle de Windows Audio Enhancements solicita UAC porque esa operación sí necesita elevación.

## ¿Qué pasa si G HUB está cerrado?

En `LogitechGHub` el estado se considera desconocido y AutoSwitch no debe cambiar la salida basándose en una lectura que no puede confirmar.

## ¿Qué significa Unknown?

`Unknown` significa que el estado no es fiable: error de `svcl`, endpoint `Disabled`, estado inesperado, fallo de G HUB, etc. La política es **no cambiar nada**.

## ¿Por qué hacen falta dos lecturas OFF?

Es debounce. Una única lectura vacía o transitoria no debe mandar el audio a los altavoces por error.

## ¿Puedo cambiar de auricular sin reinstalar?

Sí: bandeja → **Reconfigure...**. El wizard vuelve a seleccionar headset/fallback, valida `ON → OFF → ON`, determina el modo y recarga el worker.

## ¿Dónde está el log?

```text
%LOCALAPPDATA%\PROX2AutoSwitch\autoswitch.log
```

## ¿Qué versión debería usar?

Para usuarios normales, la última release estable de GitHub. Si estás probando un fix que solo existe en `main`, revisa antes la sección **Unreleased** del CHANGELOG.
''',

'FAQ-EN.md': r'''# Frequently asked questions — English

## Does it only work with Logitech PRO X 2?

No. Since v1.2.0, `WindowsEndpoint` supports headsets whose Windows render endpoint reflects the physical state. It was validated with a **Jabra Evolve 65** (`Active` when connected, `Unplugged` when powered off).

PRO X 2 uses the `LogitechGHub` fallback because Windows keeps its endpoint visible even while the physical headset is off.

## Is it universal for every wireless headset?

No such guarantee is made. It works when:

- Windows exposes a useful state transition, or
- a supported device-specific provider exists (currently PRO X 2 through G HUB).

If the wizard cannot prove a compatible method, it does not invent one.

## Why can Reconfigure take several seconds?

Bluetooth/Core Audio can be slow to expose `Active`/`Unplugged`, especially after powering a device back on. The wizard uses bounded polling instead of one fast read.

## Can my headset Item ID change?

Yes. It is a machine-local Windows endpoint identifier, not a permanent device identity. Drivers, reinstallations or Bluetooth endpoint recreation can change it.

Stable v1.2.3 already persists the latest ID observed during Reconfigure. Current `main` adds stricter hardening: if the captured ID disappears, it resolves the Render endpoint using the real `Device Name` + `Name` columns so two outputs from the same device are not confused.

## Can I copy config.json to another PC?

No. It contains endpoint IDs from the current machine.

## Does it require administrator rights?

Not for normal runtime or output switching. The Windows Audio Enhancements toggle asks for UAC because that operation requires elevation.

## What if G HUB is closed?

In `LogitechGHub` mode the physical state becomes unknown. AutoSwitch should not change output based on a state it cannot confirm.

## What does Unknown mean?

`Unknown` means the state is not trustworthy: `svcl` error, `Disabled` endpoint, unexpected state, G HUB failure, etc. The policy is **do not switch**.

## Why require two OFF readings?

Debounce. One empty/transient reading should not incorrectly send audio to the fallback.

## Can I change headset without reinstalling?

Yes: tray → **Reconfigure...**. It selects headset/fallback again, validates `ON → OFF → ON`, determines the mode and reloads the worker.

## Where is the log?

```text
%LOCALAPPDATA%\PROX2AutoSwitch\autoswitch.log
```

## Which version should I use?

Normal users should use the latest stable GitHub release. If testing a fix that exists only on `main`, check the CHANGELOG **Unreleased** section first.
''',

'Seguridad-ES.md': r'''# Seguridad — Español

## Modelo de privilegios

- El runtime normal se ejecuta **sin privilegios de administrador**.
- Cambiar la salida predeterminada no necesita elevación.
- Cambiar Windows Audio Enhancements lanza un helper puntual con **UAC**, realiza el cambio, verifica el resultado y termina.

## Descargas

El instalador obtiene SoundVolumeCommandLine (`svcl.exe`) desde NirSoft. El ZIP se valida contra un SHA-256 esperado antes de instalarlo. Si NirSoft publica otra versión y cambia el hash, el instalador **falla de forma segura**: no desactives esa comprobación sin verificar primero el hash oficial.

El instalador de una línea descarga la última release y exige también el asset `.sha256` correspondiente antes de extraerla.

## Logitech G HUB

El modo PRO X 2 utiliza un WebSocket local:

```text
ws://localhost:9010
```

No es una API pública/oficial de Logitech y puede cambiar en futuras versiones de G HUB. La conexión está limitada por timeouts y un fallo se trata como estado desconocido, no como “auricular apagado”.

## IDs y datos locales

`config.json` contiene `Item ID` de endpoints de audio del **equipo actual**. Son identificadores locales necesarios para apuntar a una salida, no secretos, y no deben copiarse entre máquinas.

El `deviceId` volátil de G HUB no se persiste; se vuelve a descubrir.

El repositorio y las releases no deberían contener GUIDs, tokens ni credenciales específicos de un usuario.

## Política fail-safe

Ante un estado `Unknown`, export CSV inválido, G HUB inaccesible o lectura no fiable, AutoSwitch **no cambia la salida**. Es preferible no actuar a interpretar un fallo como desconexión.

Consulta también [SECURITY.md](https://github.com/Ayerdi/PROX2-AutoSwitch/blob/main/SECURITY.md).
''',

'Security-EN.md': r'''# Security — English

## Privilege model

- Normal runtime runs **without administrator privileges**.
- Switching the default output does not require elevation.
- Changing Windows Audio Enhancements launches a one-off **UAC** helper, performs the change, verifies it and exits.

## Downloads

The installer gets SoundVolumeCommandLine (`svcl.exe`) from NirSoft. The ZIP is checked against an expected SHA-256 before installation. If NirSoft publishes another version and the hash changes, installation **fails safely**: do not disable that check without verifying the official hash first.

The one-line bootstrap also downloads the latest release and requires its matching `.sha256` asset before extraction.

## Logitech G HUB

PRO X 2 mode uses a local WebSocket:

```text
ws://localhost:9010
```

This is not a public/official Logitech API and can change in future G HUB versions. Connections have bounded timeouts; failure is treated as unknown state, never as “headset off”.

## IDs and local data

`config.json` stores Windows audio endpoint `Item ID`s for the **current machine**. They are local identifiers required to target outputs, not secrets, and should not be copied between machines.

The volatile G HUB `deviceId` is not persisted; it is rediscovered.

The repository/releases should never contain user-specific GUIDs, tokens or credentials.

## Fail-safe policy

On `Unknown`, invalid CSV export, inaccessible G HUB or any untrustworthy state read, AutoSwitch **does not switch output**. Doing nothing is safer than interpreting a failure as a disconnect.

See also [SECURITY.md](https://github.com/Ayerdi/PROX2-AutoSwitch/blob/main/SECURITY.md).
''',

'Desinstalar-ES.md': r'''# Desinstalar — Español

Ejecuta el desinstalador incluido en la carpeta de instalación o en el ZIP de la release:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\PROX2AutoSwitch\Desinstalar-PROX2-AutoSwitch.ps1"
```

El desinstalador intenta:

1. Detener las instancias de AutoSwitch del usuario.
2. Eliminar el acceso directo de inicio automático.
3. Borrar `%LOCALAPPDATA%\PROX2AutoSwitch\`.
4. Informar si la limpieza fue completa, parcial o si no había nada instalado.

Si el propio desinstalador se está ejecutando desde el directorio que debe borrar, programa la eliminación final de forma segura tras salir.

No desinstala Logitech G HUB ni modifica otros dispositivos/programas.

Si solo quieres cambiar auricular o fallback, **no hace falta desinstalar**: usa bandeja → **Reconfigure...**.
''',

'Uninstall-EN.md': r'''# Uninstall — English

Run the uninstaller from the installed directory or the release ZIP:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\PROX2AutoSwitch\Desinstalar-PROX2-AutoSwitch.ps1"
```

It attempts to:

1. Stop the user's AutoSwitch processes.
2. Remove the autostart shortcut.
3. Delete `%LOCALAPPDATA%\PROX2AutoSwitch\`.
4. Report whether cleanup was complete, partial or there was nothing installed.

If the uninstaller itself is running from the directory it needs to remove, final deletion is scheduled safely after it exits.

It does not uninstall Logitech G HUB or modify unrelated devices/programs.

If you only want to change headset/fallback, **do not uninstall**: use tray → **Reconfigure...**.
''',
}

ROOT.mkdir(parents=True, exist_ok=True)
for name, content in pages.items():
    (ROOT / name).write_text(content.rstrip() + '\n', encoding='utf-8')

print(f'Updated {len(pages)} wiki pages')
