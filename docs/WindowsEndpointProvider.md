# WindowsEndpointProvider — Issue técnica para el agente

> **Estado:** **SUPERSEDED.** Este documento fue el diseño original para añadir detección universal.
> La implementación final (v1.2.0) lo integró de forma más amplia: el proyecto es ahora un
> AutoSwitch universal con `DetectionMode` (`WindowsEndpoint` | `LogitechGHub`), polling por
> `System.Windows.Forms.Timer`, icono de bandeja y toggle de Audio Enhancements. Ver el plan
> en `~/.commandcode/plans/universal-audio-autoswitch.md` y el CHANGELOG v1.2.0. Se conserva
> como contexto histórico del razonamiento de providers.
> **Problema de fondo:** cambiar la detección para que el AutoSwitch funcione con cualquier auricular, no solo Logitech PRO X 2, manteniendo intacto lo que ya funciona.

## Contexto: por qué existe esta issue

El AutoSwitch actual detecta el estado físico del auricular consultando el WebSocket no oficial de Logitech G HUB (`ws://localhost:9010`). Eso limita el soporte a auriculares de Logitech con G HUB abierto.

En una prueba real con unos **Jabra Evolve 65** se observó que Windows ya cambia el **estado del endpoint de audio** según el estado físico del auricular, sin necesidad de software del fabricante:

| Estado Jabra | `svcl.exe /GetColumnValue "DefaultRenderDevice" "State"` |
|---|---|
| ENCENDIDOS | `Active` |
| APAGADOS | `Unplugged` |
| ENCENDIDOS otra vez | `Active` |

El **Item ID del endpoint no cambia** entre estados:

```text
{0.0.0.00000000}.{ed043b5e-65dc-4ba6-a847-310517ac1849}
```

Eso significa que para estos auriculares se puede detectar el estado físico mirando el `State` del endpoint de Windows, sin APIs del fabricante.

## Objetivo

Convertir la detección en un sistema de **providers** con una abstracción común:

```text
Provider → On / Off / Unknown
```

- **WindowsEndpointProvider** (nuevo): lee el `State` del endpoint de Windows. Soporta cualquier auricular cuyo endpoint refleje el estado físico (ej. Jabra Evolve 65).
- **LogitechGHubProvider** (actual): consulta el payload de batería de G HUB. Sigue soportando PRO X 2.

El runtime, el instalador y el desinstalador funcionan con cualquiera de los dos.

## Diseño de la solución

### 1. Abstracción de provider en `lib/`

Todo lo nuevo que sea lógica pura va a `lib/AutoSwitchCore.psm1` (testeable con Pester, sin dependencias de G HUB ni de `svcl.exe`). El proveedor devuelve un estado normalizado:

```powershell
# Resultado de una lectura de estado
# Status: 'On' | 'Off' | 'Unknown'
[pscustomobject]@{
    Status = 'On'        # On/Off/Unknown
    Detail = '...'       # texto para log
}
```

Ambos providers devuelven ese mismo objeto; el resto del runtime no sabe (ni necesita saber) qué provider está detrás.

### 2. WindowsEndpointProvider

- Estado físico = `State` del endpoint de render de Windows.
- La lectura usa `svcl.exe` (ya disponible en el paquete):
  - `svcl.exe /GetColumnValue "DefaultRenderDevice" "State"`.
  - **NUNCA** `/Stdout` delante de `/GetColumnValue` (bug conocido: contamina la salida y rompe el parseo; ver README "Known bug").
- Normalización a nuestro estado:
  - `Active` → `On`.
  - `Unplugged` → `Off`.
  - Cualquier otro valor (o lectura fallida) → `Unknown`, **sin cambiar la salida de audio** (regla existente: estado desconocido = no tocar nada).
- Importante: si el auricular está apagado pero **no** aparece `Unplugged` (p. ej. sigue `Active`), este provider no sirve para ese dispositivo. El instalador lo detecta en calibración.

### 3. Configuración (config.json)

Nuevo campo obligatorio:

```json
{
  "Provider": "WindowsEndpoint",
  "HeadsetName": "2- Jabra Evolve 65",
  "HeadsetId": "{0.0.0.00000000}.{ed043b5e-65dc-4ba6-a847-310517ac1849}",
  "SpeakerId": "{...}"
}
```

- `Provider` vale `WindowsEndpoint` o `LogitechGHub`.
- Los campos G HUB (`GHubDisplayName`, `GHubPort`) solo son obligatorios/validados cuando `Provider == LogitechGHub`.
- Compatibilidad hacia atrás: si `Provider` no está presente, el runtime trata la config como `LogitechGHub` (config actual v1.1.0). El instalador nuevo siempre escribe `Provider`.

### 4. Runtime

Loop de polling actual con el mismo debounce y los mismos timeouts, pero la lectura de estado se resuelve por provider:

```text
WindowsEndpoint:  leer State de DefaultRenderDevice → Active/Unplugged → On/Off/Unknown
LogitechGHub:     GET /battery/<id>/state → payload presente → On, ausente → Off
```

Reglas que **se mantienen**:

- Debounce OFF: `OffMissThreshold` respuestas consecutivas de OFF antes de cambiar a altavoces (evita flapping).
- Estado `Unknown` → no tocar la salida, log y reintento.
- Verificación del cambio: tras `svcl /SetDefault <Item ID> all`, releer el Item ID predeterminado y comparar; un solo reintento si falla.
- Límites duros de tiempo en WebSocket (solo G HUB).
- Mutex por usuario, inicio invisible vía `wscript.exe`, log con rotación.

### 5. Instalador

Dejar de preguntar implícitamente por "PRO X 2 + altavoces". El flujo nuevo es:

1. **Seleccionar el dispositivo a vigilar** (el actual default en Windows, p. ej. `2- Jabra Evolve 65`).
2. **Seleccionar el dispositivo de fallback** (p. ej. `Altavoces AMAZON`).
3. **Auto-detección del provider** (el usuario no tiene que saber nada de providers):
   - Tras capturar los dos endpoints, el asistente pide: *"Apaga el auricular y pulsa ENTER"*.
   - Se lee el `State` del auricular:
     - `Active` → `Unplugged`: **Windows detecta el estado físico directamente** → `Provider = WindowsEndpoint`.
     - `Active` → `Active` (o `Unknown`): Windows no lo detecta. El asistente busca un provider específico de dispositivo:
       - Si es un Logitech (por nombre) y G HUB responde → `Provider = LogitechGHub`.
       - Si no hay provider compatible → abortar con mensaje claro: *"Windows no puede detectar el estado físico de este auricular y no hay provider compatible"*.
4. **Probar de verdad ambos cambios** de salida (ya existe `Test-SetDefault`).
5. Guardar `config.json` con `Provider` y los campos correspondientes, mantener `InstalledAt`.

### 6. Desinstalador / Verificador

- Desinstalador: sin cambios de fondo (sigue matando el proceso y limpiando autostart + archivos).
- Verificador: mostrar `Provider` de config y, si es `WindowsEndpoint`, comprobar el estado `Active`/`Unplugged` en vez de (o además de) probar el puerto G HUB.

## Fases de implementación (orden)

1. **WindowsEndpointProvider**: crear la lógica pura en `lib/` con tests Pester (normalización `Active`→`On`, `Unplugged`→`Off`, valores raros→`Unknown`, Item ID de endpoint).
2. **Probarlo en máquina real con los Jabra Evolve 65**: validar la transición `Active ↔ Unplugged` durante un día de uso normal (aumenta la confianza del proveedor de detección sin tocar nada más).
3. **Refactor runtime**: ambos providers devuelven `On/Off/Unknown`; el loop usa el provider de config.
4. **Instalador con auto-selección de provider** (paso 3 del flujo de instalación).
5. **Backlog / futuro** (NO en esta issue):
   - Sustituir el polling por eventos nativos de Windows (`IMMNotificationClient`) para que `Active ↔ Unplugged` sea prácticamente instantáneo.
   - Botón "Disable Audio Enhancements" para endpoints que lo necesiten.
   - Renombrar el proyecto a largo plazo a "Audio AutoSwitch" (manteniendo PRO X 2 como dispositivo especialmente soportado); implica actualizar URLs de `install.ps1` en README/site.

## Criterios de aceptación

- [ ] El runtime con `Provider = WindowsEndpoint` cambia a auriculares cuando el endpoint pasa a `Active` y a altavoces cuando pasa a `Unplugged`.
- [ ] El runtime con `Provider = LogitechGHub` sigue funcionando igual que hoy (regresión: sin cambios de comportamiento).
- [ ] Instalador detecta automáticamente `WindowsEndpoint` con un auricular Jabra y `LogitechGHub` con un PRO X 2, sin preguntar al usuario por providers.
- [ ] `Unknown` nunca cambia la salida de audio.
- [ ] Debounce OFF se mantiene en ambos providers.
- [ ] Config v1.1.0 sin `Provider` se interpreta como `LogitechGHub` (compatibilidad hacia atrás).
- [ ] Tests Pester nuevos en `tests/` cubren la normalización del estado y los casos `Unknown`.
- [ ] CI `validate.yml` pasa (sintaxis, PSScriptAnalyzer, Pester).

## Riesgos y mitigaciones

- **`State` puede no reflejar el estado físico en todos los auriculares** (algunos se quedan `Active` apagados). Mitigación: la auto-detección del instalador descarta ese caso y no deja instalar con `WindowsEndpoint` si no se observa `Active → Unplugged`.
- **`svcl.exe /GetColumnValue ... State`**: confirmar en SOURCES.md el valor exacto que devuelve (columna `State`). Si cambia el formato de salida, `Get-RenderItemIdFromText` y la normalización se actualizan; los tests Pester lo protegen.
- **Windows puede recrear endpoints** (Item ID cambia): el instalador ya captura IDs del Windows actual; no perseguir cambios de ID en runtime en esta issue.

## Archivos afectados (estimación)

- `lib/AutoSwitchCore.psm1` — normalización de estado + lógica de provider.
- `Runtime-PROX2-AutoSwitch.ps1` — resolver estado por provider.
- `Instalar-PROX2-AutoSwitch.ps1` — flujo de calibración + auto-detección + `Provider` en config.
- `Desinstalar-PROX2-AutoSwitch.ps1` — sin cambios funcionales (revisar).
- `Verificar-PROX2-AutoSwitch.ps1` — mostrar `Provider` y estado del endpoint.
- `tests/AutoSwitchCore.Tests.ps1` — nuevos tests.
- `README.md`, `AGENT.md`, `SOURCES.md`, `CHANGELOG.md`, `site/` — documentación.
