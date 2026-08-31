"""Validate that a release is coherent before and after packaging.

The canonical version lives in the repository-root VERSION file. This script is
intentionally version-agnostic so future releases can reuse the same checks.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEMVER = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")

CRITICAL_PACKAGE_FILES = (
    "Install.cmd",
    "Verify.cmd",
    "Uninstall.cmd",
    "Install-AutoSwitch.ps1",
    "Verify-AutoSwitch.ps1",
    "Uninstall-AutoSwitch.ps1",
    "Instalar-PROX2-AutoSwitch.ps1",
    "Verificar-PROX2-AutoSwitch.ps1",
    "Desinstalar-PROX2-AutoSwitch.ps1",
    "Runtime-PROX2-AutoSwitch.ps1",
    "install.ps1",
    "lib/AutoSwitchCore.psm1",
    "lib/LogitechProX2Centurion.psm1",
    "lib/SteelSeriesNova5.psm1",
    "tools/Test-LogitechProX2Centurion.ps1",
    "tools/Test-SteelSeriesNova5Hid.ps1",
    "README.md",
    "CHANGELOG.md",
    "SOURCES.md",
    "SECURITY.md",
    "SUPPORT.md",
    "LICENSE",
)

EXPECTED_RELEASE_ASSETS = (
    "Audio-AutoSwitch.zip",
    "Audio-AutoSwitch.zip.sha256",
    "PROX2-AutoSwitch-v{version}.zip",
    "PROX2-AutoSwitch-v{version}.zip.sha256",
)


def fail(message: str) -> None:
    raise SystemExit(message)


def text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8-sig")


def canonical_version() -> str:
    path = ROOT / "VERSION"
    if not path.is_file():
        fail("VERSION file is missing")
    version = path.read_text(encoding="utf-8-sig").strip()
    if not SEMVER.fullmatch(version):
        fail(f"VERSION is not MAJOR.MINOR.PATCH: {version!r}")
    return version


def resolve_version(requested: str | None) -> str:
    current = canonical_version()
    version = requested.strip() if requested else current
    if not SEMVER.fullmatch(version):
        fail(f"Release version is not MAJOR.MINOR.PATCH: {version!r}")
    if version != current:
        fail(f"Requested version {version} does not match canonical VERSION {current}")
    return version


def require_contains(path: str, needle: str, description: str | None = None) -> None:
    if needle not in text(path):
        fail(f"{path} is missing {description or needle!r}")


def require_regex(path: str, pattern: str, expected: str, label: str) -> None:
    match = re.search(pattern, text(path), re.MULTILINE)
    if not match:
        fail(f"{path}: could not find {label}")
    actual = match.group(1)
    if actual != expected:
        fail(f"{path}: {label} mismatch: expected {expected}, found {actual}")


def check_source(version: str) -> None:
    release_notes = f"docs/RELEASE-NOTES-v{version}.md"
    required = (
        "VERSION",
        "README.md",
        "CHANGELOG.md",
        "Instalar-PROX2-AutoSwitch.ps1",
        "scripts/check-repository.py",
        "scripts/build-release.sh",
        "scripts/check-release-readiness.py",
        "scripts/publish-release.sh",
        ".github/workflows/validate.yml",
        ".github/workflows/release-readiness.yml",
        ".github/workflows/publish-current-release.yml",
        ".github/workflows/post-release-verify.yml",
        ".github/workflows/sync-wiki.yml",
        ".github/workflows/pages.yml",
        "docs/RELEASE-PROCESS.md",
        "wiki/Home.md",
        "wiki/Inicio.md",
        "site/index.html",
        release_notes,
    )
    missing = [item for item in required if not (ROOT / item).is_file()]
    if missing:
        fail("Release-readiness files are missing: " + ", ".join(missing))

    require_regex(
        "README.md",
        r"\*\*Stable release:\s*(?:\[)?v([0-9]+\.[0-9]+\.[0-9]+)",
        version,
        "stable release",
    )
    require_regex(
        "wiki/Home.md",
        r"\*\*Stable release:\s*v([0-9]+\.[0-9]+\.[0-9]+)",
        version,
        "stable release",
    )
    require_regex(
        "wiki/Inicio.md",
        r"\*\*Versi[^:]*n estable:\s*v([0-9]+\.[0-9]+\.[0-9]+)",
        version,
        "stable release",
    )
    require_regex(
        "site/index.html",
        r"<strong>v([0-9]+\.[0-9]+\.[0-9]+)</strong>\s*stable",
        version,
        "stable badge",
    )
    require_regex(
        "Instalar-PROX2-AutoSwitch.ps1",
        r'^\s*Version\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"\s*$',
        version,
        "generated config version",
    )

    require_contains("CHANGELOG.md", f"## [{version}]", "current CHANGELOG section")
    require_contains(release_notes, f"# Audio AutoSwitch v{version}", "release-notes heading")

    validate = text(".github/workflows/validate.yml")
    if "cat VERSION" not in validate:
        fail("validate.yml must read the canonical VERSION file")
    hardcoded_build = re.findall(r"build-release\.sh\s+([0-9]+\.[0-9]+\.[0-9]+)", validate)
    if hardcoded_build:
        fail("validate.yml contains a hard-coded release version: " + ", ".join(hardcoded_build))

    readiness = text(".github/workflows/release-readiness.yml")
    for marker in (
        "name: release-readiness",
        "workflow_dispatch:",
        "check-release-readiness.py",
        "PSScriptAnalyzer",
        "Invoke-Pester",
        "Build deterministic release twice",
    ):
        if marker not in readiness:
            fail(f"release-readiness.yml is missing required marker: {marker}")

    publisher = text(".github/workflows/publish-current-release.yml")
    for marker in (
        "name: publish-current-release",
        "workflow_run:",
        "workflows: [release-readiness]",
        "github.event.workflow_run.conclusion == 'success'",
        "remote_main=",
        "check-release-readiness.py --version \"$VERSION\" --source-only",
        "check-release-readiness.py --version \"$VERSION\" --package-only",
        "gh release create \"$tag\"",
    ):
        if marker not in publisher:
            fail(f"publish-current-release.yml is missing release gate marker: {marker}")

    sync_wiki = text(".github/workflows/sync-wiki.yml")
    for marker in (
        "name: sync-wiki",
        "workflow_dispatch:",
        "VERSION",
        "scripts/publish-wiki.sh --apply",
    ):
        if marker not in sync_wiki:
            fail(f"sync-wiki.yml is missing required marker: {marker}")

    pages = text(".github/workflows/pages.yml")
    for marker in (
        "workflow_dispatch:",
        "name: github-pages-${{ github.run_attempt }}",
        "artifact_name: github-pages-${{ github.run_attempt }}",
    ):
        if marker not in pages:
            fail(f"pages.yml is missing rerun-safety marker: {marker}")

    post = text(".github/workflows/post-release-verify.yml")
    for marker in (
        "name: post-release-verify",
        "release:",
        "types: [published]",
        "check-release-readiness.py",
        "raw.githubusercontent.com/wiki/Ayerdi/PROX2-AutoSwitch/Home.md",
        "ayerdi.github.io/PROX2-AutoSwitch/",
    ):
        if marker not in post:
            fail(f"post-release-verify.yml is missing required marker: {marker}")

    local_publisher = text("scripts/publish-release.sh")
    for marker in (
        "VERSION",
        "check-release-readiness.py",
        "release-readiness.yml",
    ):
        if marker not in local_publisher:
            fail(f"publish-release.sh is missing release gate marker: {marker}")

    print(f"Source release readiness OK for v{version}.")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024, ), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_checksum(path: Path) -> tuple[str, str]:
    fields = path.read_text(encoding="utf-8").strip().split()
    if len(fields) != 2 or not re.fullmatch(r"[0-9a-fA-F]{64}", fields[0]):
        fail(f"Invalid SHA-256 file format: {path}")
    return fields[0].lower(), fields[1].lstrip("*")


def check_package(version: str, dist: Path) -> None:
    versioned = dist / f"PROX2-AutoSwitch-v{version}.zip"
    alias = dist / "Audio-AutoSwitch.zip"
    versioned_sum = dist / f"PROX2-AutoSwitch-v{version}.zip.sha256"
    alias_sum = dist / "Audio-AutoSwitch.zip.sha256"

    expected_assets = {item.format(version=version) for item in EXPECTED_RELEASE_ASSETS}
    missing = [name for name in sorted(expected_assets) if not (dist / name).is_file()]
    if missing:
        fail("Missing release assets: " + ", ".join(missing))

    versioned_hash = sha256(versioned)
    alias_hash = sha256(alias)
    if versioned_hash != alias_hash:
        fail("Versioned ZIP and Audio-AutoSwitch.zip are not byte-identical")
    if versioned.read_bytes() != alias.read_bytes():
        fail("Versioned ZIP and Audio-AutoSwitch.zip differ despite hash comparison")

    expected_hash, expected_name = parse_checksum(versioned_sum)
    if expected_name != versioned.name or expected_hash != versioned_hash:
        fail(f"Checksum does not match {versioned.name}")

    alias_expected_hash, alias_expected_name = parse_checksum(alias_sum)
    if alias_expected_name != alias.name or alias_expected_hash != alias_hash:
        fail(f"Checksum does not match {alias.name}")

    prefix = f"PROX2-AutoSwitch-v{version}/"
    with zipfile.ZipFile(versioned) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            fail("Release ZIP contains duplicate entries")
        if any(name.startswith("/") or ".." in Path(name).parts for name in names):
            fail("Release ZIP contains an unsafe path")
        if any(not name.startswith(prefix) for name in names):
            fail(f"Release ZIP contains entries outside {prefix}")

        missing_package = [
            rel for rel in CRITICAL_PACKAGE_FILES if f"{prefix}{rel}" not in names
        ]
        if missing_package:
            fail("Release ZIP is missing critical files: " + ", ".join(missing_package))

        packaged_readme = archive.read(f"{prefix}README.md").decode("utf-8-sig")
        if f"v{version}" not in packaged_readme:
            fail("Packaged README does not identify the release version")
        packaged_changelog = archive.read(f"{prefix}CHANGELOG.md").decode("utf-8-sig")
        if f"## [{version}]" not in packaged_changelog:
            fail("Packaged CHANGELOG does not contain the release section")

    print(f"Packaged release readiness OK for v{version}: {versioned_hash}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", help="Expected MAJOR.MINOR.PATCH; defaults to VERSION")
    parser.add_argument("--dist", default=str(ROOT / "dist"), help="Release asset directory")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--source-only", action="store_true")
    mode.add_argument("--package-only", action="store_true")
    args = parser.parse_args()

    version = resolve_version(args.version)
    if not args.package_only:
        check_source(version)
    if not args.source_only:
        check_package(version, Path(args.dist).resolve())
    return 0


if __name__ == "__main__":
    sys.exit(main())
