#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"
[[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'Usage: %s MAJOR.MINOR.PATCH\n' "$0" >&2; exit 2; }
CANONICAL_VERSION="$(tr -d '\r\n' < "${ROOT_DIR}/VERSION")"
[[ "${VERSION}" == "${CANONICAL_VERSION}" ]] || { printf 'Requested version %s does not match VERSION=%s\n' "$VERSION" "$CANONICAL_VERSION" >&2; exit 2; }
DIST="${ROOT_DIR}/dist"; mkdir -p "$DIST"
ARCHIVE="${DIST}/PROX2-AutoSwitch-v${VERSION}.zip"
python3 - "$ROOT_DIR" "$ARCHIVE" "$VERSION" <<'PY'
import pathlib, stat, sys, zipfile
root=pathlib.Path(sys.argv[1]); archive=pathlib.Path(sys.argv[2]); version=sys.argv[3]
prefix=f'PROX2-AutoSwitch-v{version}'
paths=['VERSION','Install.cmd','Verify.cmd','Uninstall.cmd','Install-AutoSwitch.ps1','Verify-AutoSwitch.ps1','Uninstall-AutoSwitch.ps1','Instalar-PROX2-AutoSwitch.ps1','Verificar-PROX2-AutoSwitch.ps1','Desinstalar-PROX2-AutoSwitch.ps1','Runtime-PROX2-AutoSwitch.ps1','Toggle-AudioEnhancements.ps1','install.ps1','lib/AutoSwitchCore.psm1','lib/LogitechGHub.psm1','lib/SteelSeriesNova5.psm1','tools/Test-SteelSeriesNova5Hid.ps1','assets/icon.ico','README.md','AGENT.md','SOURCES.md','SECURITY.md','SUPPORT.md','CONTRIBUTING.md','CHANGELOG.md','LICENSE']
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as zf:
  for rel in sorted(paths,key=str.casefold):
    p=root/rel
    if not p.is_file(): raise SystemExit(f'Missing release file: {rel}')
    info=zipfile.ZipInfo(f'{prefix}/{rel}'); info.date_time=(1980,1,1,0,0,0); info.compress_type=zipfile.ZIP_DEFLATED; info.external_attr=(stat.S_IFREG|0o644)<<16
    zf.writestr(info,p.read_bytes(),compress_type=zipfile.ZIP_DEFLATED,compresslevel=9)
PY
name="$(basename "$ARCHIVE")"; (cd "$DIST" && sha256sum "$name") > "${ARCHIVE}.sha256"
cp "$ARCHIVE" "${DIST}/Audio-AutoSwitch.zip"
(cd "$DIST" && sha256sum Audio-AutoSwitch.zip) > "${DIST}/Audio-AutoSwitch.zip.sha256"
