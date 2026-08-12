from pathlib import Path
import re


def read(path):
    return Path(path).read_text(encoding='utf-8-sig')


def write(path, text):
    Path(path).write_text(text, encoding='utf-8')

required = {
    'Install.cmd': None,
    'Verify.cmd': None,
    'Uninstall.cmd': None,
    'install.ps1': 'Audio AutoSwitch',
    'Instalar-PROX2-AutoSwitch.ps1': 'Wait-ForHeadsetInstallState',
    'Verificar-PROX2-AutoSwitch.ps1': '[SKIP] G HUB (not used in WindowsEndpoint mode)',
    '.github/workflows/release.yml': 'Audio-AutoSwitch.zip',
    '.github/workflows/validate.yml': "'Install.cmd'",
}
for path, marker in required.items():
    p = Path(path)
    if not p.exists():
        raise SystemExit(f'missing expected patched file: {path}')
    if marker and marker not in read(p):
        raise SystemExit(f'missing expected marker in {path}: {marker}')

p = Path('README.md')
text = read(p)

if '## Quick start' not in text:
    anchor = 'See it live on the [project page](https://ayerdi.github.io/PROX2-AutoSwitch/).\n'
    if anchor not in text:
        raise SystemExit('README project-page anchor not found')
    quick = '''

## Quick start

### Recommended: download the ZIP

1. Open the [latest release](https://github.com/Ayerdi/PROX2-AutoSwitch/releases/latest) and download `Audio-AutoSwitch.zip`.
2. Extract the ZIP to a normal folder.
3. Double-click **`Install.cmd`**.
4. Pick your headset and fallback output, then follow the ON → OFF → ON wizard.
5. When installation finishes, turn the headset off/on once to confirm the real switch.

`Install.cmd` is only a small launcher for the PowerShell installer; all installation logic remains in the reviewed `.ps1` files. The release also includes **`Verify.cmd`** and **`Uninstall.cmd`** for double-click diagnostics/removal.

### One-command install

If you prefer PowerShell, this bootstrap downloads the latest versioned release ZIP plus its SHA-256 checksum, verifies it, and then starts the same installer:

```powershell
powershell.exe -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/Ayerdi/PROX2-AutoSwitch/main/install.ps1 | iex"
```
'''
    text = text.replace(anchor, anchor + quick, 1)

pattern = re.compile(
    r'## Installation\n\n'
    r'\*\*One click\*\*.*?'
    r'\nThe installer will:\n',
    re.S,
)
replacement = '''## Installation details

The recommended ZIP path is **extract → double-click `Install.cmd`**. If Windows has marked the downloaded scripts as blocked and the launcher cannot run them, open PowerShell in the extracted folder and run:

```powershell
Get-ChildItem . -Filter *.ps1 | Unblock-File
powershell.exe -ExecutionPolicy Bypass -File ".\\Instalar-PROX2-AutoSwitch.ps1"
```

The installer will:
'''
text, n = pattern.subn(replacement, text, count=1)
if n != 1:
    raise SystemExit(f'README installation regex matched {n} blocks')

text = text.replace(
    'ask you to turn the headset OFF and back ON — if Windows reflects `Active → Unplugged → Active`, it picks `WindowsEndpoint` mode automatically;',
    'ask you to turn the headset OFF and back ON — it polls Windows for up to 15 s / 15 s / 20 s instead of trusting one fast Bluetooth reading; if Windows reflects `Active → Unplugged → Active`, it picks `WindowsEndpoint` mode automatically; if the endpoint is recreated with a new Item ID during that cycle, the installer re-resolves it by `Device Name` + `Name` and keeps the newest ID;'
)
text = text.replace(
    '- `install.ps1` — one-click bootstrap: fetches the latest release ZIP and its `.sha256`, verifies the hash, then runs the installer.',
    '- `install.ps1` — one-command bootstrap: fetches the latest versioned release ZIP and its `.sha256`, verifies the hash, then runs the installer.\n- `Install.cmd` / `Verify.cmd` / `Uninstall.cmd` — tiny double-click launchers; the real logic remains in PowerShell.'
)
write(p, text)

p = Path('CHANGELOG.md')
text = read(p)
needle = '## [Unreleased]\n'
if needle not in text:
    raise SystemExit('CHANGELOG: Unreleased heading not found')
if 'Double-click `Install.cmd`' not in text:
    notes = '''## [Unreleased]

### Added
- Double-click `Install.cmd`, `Verify.cmd`, and `Uninstall.cmd` launchers for users who download the release ZIP.
- Release packaging now also publishes a stable `Audio-AutoSwitch.zip` + SHA-256 alias in addition to the versioned archive.

### Fixed
- Clean installation now polls Bluetooth/Core Audio transitions for 15 s / 15 s / 20 s and refreshes a recreated headset Item ID by `Device Name` + `Name`, matching the hardened Reconfigure flow.
- The verifier no longer reports G HUB as a failure for generic `WindowsEndpoint` installations.
- The one-command bootstrap now uses English/generic Audio AutoSwitch wording.
- Removed leftover one-shot documentation workflows/scripts from `.github/`.
'''
    text = text.replace(needle, notes, 1)
write(p, text)

keep = {
    'tmp_onboarding_hardening.py',
    'tmp_onboarding_finish.py',
    'tmp-onboarding-hardening.yml',
}
for path in list(Path('.github').glob('tmp_*')) + list(Path('.github/workflows').glob('tmp-*.yml')):
    if path.name not in keep and path.is_file():
        path.unlink()

print('Onboarding finishing patch applied.')
