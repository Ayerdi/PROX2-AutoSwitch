"""Repository-level checks shared by CI and release preparation."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION_FILE = ROOT / "VERSION"

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
    "scripts/build-release.sh",
    "scripts/run-gitleaks.sh",
    ".github/workflows/validate.yml",
    ".github/workflows/release.yml",
    "wiki/Home.md",
    "wiki/Inicio.md",
    "site/index.html",
)

CURRENT_VERSION_FILES = (
    "README.md",
    "wiki/Home.md",
    "wiki/Inicio.md",
    "site/index.html",
)


def fail(message: str) -> None:
    raise SystemExit(message)


def current_version() -> str:
    if not VERSION_FILE.is_file():
        fail("VERSION is missing")
    version = VERSION_FILE.read_text(encoding="utf-8-sig").strip()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        fail(f"VERSION must contain MAJOR.MINOR.PATCH, got: {version!r}")
    return version


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
    version = current_version()
    marker = f"v{version}"
    missing = []
    for relative in CURRENT_VERSION_FILES:
        text = (ROOT / relative).read_text(encoding="utf-8-sig")
        if marker not in text:
            missing.append(relative)
    if missing:
        fail(f"Current stable marker {marker} is missing from: " + ", ".join(missing))

    changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8-sig")
    if f"## [{version}]" not in changelog:
        fail(f"CHANGELOG.md has no {version} release section")


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
    permanent_release = workflows / "release.yml"
    if not permanent_release.is_file():
        fail(".github/workflows/release.yml is required")

    legacy = sorted(workflows.glob("release-v*.yml")) + sorted(workflows.glob("release-v*.yaml"))
    if legacy:
        names = ", ".join(path.name for path in legacy)
        fail("Version-specific release workflows are not allowed: " + names)

    for relative in (".github/workflows/validate.yml", ".github/workflows/release.yml"):
        text = (ROOT / relative).read_text(encoding="utf-8-sig")
        if "VERSION" not in text:
            fail(f"{relative} must read the canonical VERSION file")


def main() -> int:
    check_required_files()
    check_no_temporary_github_files()
    check_current_version()
    check_wiki_links()
    check_release_workflows()
    print(f"Repository quality checks OK (v{current_version()}).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
