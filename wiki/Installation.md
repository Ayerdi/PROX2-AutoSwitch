# Installation

## One-command installer

```powershell
powershell.exe -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/Ayerdi/PROX2-AutoSwitch/main/install.ps1 | iex"
```

The bootstrap downloads the latest release ZIP and its `.sha256`, verifies SHA-256, extracts the package and launches the real installer.

## Manual installation

1. Download the latest ZIP and `.sha256` from Releases.
2. Verify the checksum.
3. Extract the **whole** ZIP to a normal folder.
4. Run:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Install-AutoSwitch.ps1
```

The older `Instalar-PROX2-AutoSwitch.ps1` filename remains as a compatibility entrypoint.

The wizard lists output devices, lets you choose headset/fallback, observes a real OFF/ON cycle, chooses `WindowsEndpoint` when Windows provides a usable signal and falls back to G HUB only for a confirmed PRO X 2.

[[Instalacion|Leer en español]]
