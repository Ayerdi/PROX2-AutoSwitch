# PRO X 2 LIGHTSPEED AutoSwitch

Automatically switch your Windows default audio output when you put on or take off your **Logitech PRO X 2 Lightspeed** headset.

- **PRO X 2 powered on** → Windows uses the headset output.
- **PRO X 2 powered off** → Windows falls back to your alternative output (e.g. PC speakers).
- The LIGHTSPEED dongle can stay plugged in.
- Runs in the background with **no PowerShell window at login**.

## Why this exists

Wireless headsets keep their USB/LIGHTSPEED endpoint visible to Windows even when the physical headset is turned off. So Windows doesn't know it should switch back to your speakers.

The manual dance got old fast:

1. Take off the headset.
2. Open the sound settings.
3. Change the default output.
4. Put the headset back on.
5. Repeat.

This project removes that friction: switch the output just by turning the headset on or off.

## How it works

Tested on 2026-08-07: while the PRO X 2 is powered on, Logitech G HUB's battery query returns a `payload`; when powered off, it doesn't; power on again and it comes back. AutoSwitch uses that signal.

```
PRO X 2
   │
   ▼
Logitech G HUB
ws://localhost:9010
   │
   ├── GET /devices/list
   │      └── locate the PRO X 2 extendedDisplayName
   │
   └── GET /battery/<deviceId>/state
             │
             ├── payload present -> ON
             └── payload absent  -> OFF
                         │
                         ▼
             SoundVolumeCommandLine
                         │
             /SetDefault <Item ID> all
                         │
                         ▼
                      Windows
```

## Requirements

- Windows 10/11 x64.
- Logitech G HUB installed, open, and recognizing the PRO X 2.
- Internet connection during install (downloads `svcl.exe` from NirSoft).
- PowerShell 5.1 or newer.

No admin rights should be required for normal operation.

## Installation

1. Install Logitech G HUB and confirm it detects the PRO X 2.
2. Extract the whole ZIP to a normal folder. Don't run the installer from inside the ZIP.
3. Open PowerShell in that folder.
4. If Windows blocked the downloaded scripts:

```powershell
Get-ChildItem . -Filter *.ps1 | Unblock-File
```

5. Run:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\Instalar-PROX2-AutoSwitch.ps1"
```

The installer will:

- download SoundVolumeCommandLine from NirSoft;
- verify its SHA-256 before running it;
- connect to G HUB at `ws://localhost:9010`;
- locate the PRO X 2;
- ask you to manually select the headset as the default output;
- capture the real **Item ID** of the current Windows;
- ask you to select the alternative output;
- capture its Item ID;
- actually test both switches;
- save the configuration;
- install the runtime;
- create an invisible autostart entry via `wscript.exe`;
- start AutoSwitch.

### Important

Windows audio `Item ID`s are **not reused** across installs. The installer is designed to capture them from your current Windows. Don't copy `config.json` from another machine.

The `dev000000XX` ID from G HUB isn't persisted either. The runtime keeps the `extendedDisplayName` and discovers the current `deviceId` at startup.

> The PowerShell scripts are the original working versions and their on-screen messages are in Spanish. They work unchanged on any locale; only the UI text is Spanish.

## Where it installs

```text
%LOCALAPPDATA%\PROX2AutoSwitch\
```

Main contents:

```text
PROX2AutoSwitch.ps1
config.json
svcl.exe
Iniciar-Oculto.vbs
autoswitch.log
Desinstalar-PROX2-AutoSwitch.ps1
Verificar-PROX2-AutoSwitch.ps1
```

Autostart is created in the user's Startup folder as:

```text
PRO X 2 AutoSwitch.lnk
```

That shortcut runs `wscript.exe`, which starts PowerShell hidden — no console window at login.

## Verify it works

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\Verificar-PROX2-AutoSwitch.ps1"
```

Or use the installed copy:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\PROX2AutoSwitch\Verificar-PROX2-AutoSwitch.ps1"
```

Manual test:

1. Power on the PRO X 2.
2. Wait ~1–2 seconds.
3. Windows should select the headset.
4. Power them off.
5. After two consecutive checks (~3 seconds), Windows should select the alternative output.

Two consecutive empty responses are required before treating the headset as off, to avoid flapping on a one-off G HUB response.

## Log

```text
%LOCALAPPDATA%\PROX2AutoSwitch\autoswitch.log
```

Expected example:

```text
PRO X 2 AutoSwitch iniciado.
PRO X 2 detectado por G HUB: PRO X 2 Lightspeed Gaming Headset (dev...)
Conectado con G HUB.
Salida cambiada -> ...
Salida cambiada -> ...
```

## Uninstall

From the package:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\Desinstalar-PROX2-AutoSwitch.ps1"
```

or from the installation:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\PROX2AutoSwitch\Desinstalar-PROX2-AutoSwitch.ps1"
```

## Known bug — do NOT reintroduce

`svcl.exe /GetColumnValue` already writes the value to stdout. Do **not** use:

```powershell
svcl.exe /Stdout /GetColumnValue ...
```

In an earlier implementation `/Stdout` prepended item info (`1 item found:`, name, etc.) and corrupted the Item ID, so `/SetDefault` got an invalid identifier and answered `No items found`.

The correct form used in this version is:

```powershell
svcl.exe /GetColumnValue "DefaultRenderDevice" "Item ID"
```

then extract only:

```text
{0.0.0.00000000}.{GUID}
```

## Security notes

- The G HUB WebSocket `localhost:9010` is **not an officially supported Logitech API**. It's a reverse-engineered local interface used by third-party projects. Logitech can change it in future G HUB releases. If it stops working after a G HUB update, see `AGENT.md`.
- The installer downloads `svcl-x64.zip` from NirSoft and verifies its SHA-256. If NirSoft ships a new version the hash may change and the installer **fails safely**. Don't remove that check.

## Repository layout

- `Instalar-PROX2-AutoSwitch.ps1` — clean install from scratch.
- `Runtime-PROX2-AutoSwitch.ps1` — the runtime copied to `%LOCALAPPDATA%`.
- `Desinstalar-PROX2-AutoSwitch.ps1` — removes process, autostart and files.
- `Verificar-PROX2-AutoSwitch.ps1` — quick diagnostics.
- `AGENT.md` — context so an AI agent can maintain/rebuild the project.
- `SOURCES.md` — verified technical references.
