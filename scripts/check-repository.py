"""Repository-level checks shared by CI and release preparation."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION_FILE = ROOT / "VERSION"
SEMVER = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")


def fail(message: str) -> None:
    raise SystemExit(message)


def read_text(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8-sig")


def read_current_version() -> str:
    if not VERSION_FILE.is_file():
        fail("VERSION file is missing")
    version = VERSION_FILE.read_text(encoding="utf-8-sig").strip()
    if not SEMVER.fullmatch(version):
        fail(f"VERSION is not MAJOR.MINOR.PATCH: {version!r}")
    return version


CURRENT_VERSION = read_current_version()
RELEASE_NOTES = f"docs/RELEASE-NOTES-v{CURRENT_VERSION}.md"

REQUIRED_FILES = (
    "VERSION",
    "README.md",
    "LICENSE",
    "SECURITY.md",
    "SUPPORT.md",
    "CONTRIBUTING.md",
    "CODE_OF_CONDUCT.md",
    "CHANGELOG.md",
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
    "Toggle-AudioEnhancements.ps1",
    "lib/AutoSwitchCore.psm1",
    "lib/LogitechProX2Centurion.psm1",
    "tools/Test-LogitechProX2Centurion.ps1",
    "scripts/build-release.sh",
    "scripts/run-gitleaks.sh",
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
    RELEASE_NOTES,
)

CURRENT_VERSION_FILES = (
    "README.md",
    "wiki/Home.md",
    "wiki/Inicio.md",
    "site/index.html",
)


def check_required_files() -> None:
    missing = [name for name in REQUIRED_FILES if not (ROOT / name).is_file()]
    if missing:
        fail("Missing required repository files: " + ", ".join(missing))


def check_no_temporary_github_files() -> None:
    github = ROOT / ".github"
    offenders = [
        path.relative_to(ROOT).as_posix()
        for path in github.rglob("*")
        if path.is_file() and ("tmp" in path.name.casefold() or "temporary" in path.name.casefold())
    ]
    if offenders:
        fail("Temporary GitHub files must not be committed: " + ", ".join(offenders))


def check_current_version() -> None:
    marker = f"v{CURRENT_VERSION}"
    missing = []
    for relative in CURRENT_VERSION_FILES:
        if marker not in read_text(relative):
            missing.append(relative)
    if missing:
        fail(f"Current stable marker {marker} is missing from: " + ", ".join(missing))

    changelog = read_text("CHANGELOG.md")
    if f"## [{CURRENT_VERSION}]" not in changelog:
        fail(f"CHANGELOG.md has no {CURRENT_VERSION} release section")

    installer = read_text("Instalar-PROX2-AutoSwitch.ps1")
    installer_version = re.search(
        r'^\s*Version\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"\s*$',
        installer,
        re.MULTILINE,
    )
    if not installer_version:
        fail("Installer config Version assignment was not found")
    if installer_version.group(1) != CURRENT_VERSION:
        fail(
            "Installer config version mismatch: "
            f"expected {CURRENT_VERSION}, found {installer_version.group(1)}"
        )

    validate = read_text(".github/workflows/validate.yml")
    if "cat VERSION" not in validate:
        fail("validate.yml does not consume the canonical VERSION file")
    hardcoded = re.findall(r"build-release\.sh\s+([0-9]+\.[0-9]+\.[0-9]+)", validate)
    if hardcoded:
        fail("validate.yml hard-codes release version(s): " + ", ".join(hardcoded))

    release_notes = read_text(RELEASE_NOTES)
    if f"# Audio AutoSwitch v{CURRENT_VERSION}" not in release_notes:
        fail(f"{RELEASE_NOTES} heading does not match current version {CURRENT_VERSION}")


def check_wiki_links() -> None:
    wiki = ROOT / "wiki"
    page_names = {path.stem for path in wiki.glob("*.md")}
    broken: list[str] = []
    pattern = re.compile(r"\[\[([^\]|]+)(?:\|([^\]]+))?\]\]")
    for path in wiki.glob("*.md"):
        text = path.read_text(encoding="utf-8-sig")
        for page, _label in pattern.findall(text):
            target = page.strip()
            if target.startswith("http://") or target.startswith("https://"):
                continue
            if target not in page_names:
                broken.append(f"{path.name} -> {target}")
    if broken:
        fail("Broken Wiki links: " + "; ".join(sorted(broken)))


def check_release_workflows() -> None:
    workflows = ROOT / ".github" / "workflows"
    deprecated = workflows / "release.yml"
    if deprecated.exists():
        fail("release.yml is deprecated; use publish-current-release.yml")

    publisher = read_text(".github/workflows/publish-current-release.yml")
    if "workflows: [release-readiness]" not in publisher:
        fail("publish-current-release.yml must be gated by release-readiness")


def main() -> int:
    check_required_files()
    check_no_temporary_github_files()
    check_current_version()
    check_wiki_links()
    check_release_workflows()
    print(f"Repository quality checks OK for v{CURRENT_VERSION}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
