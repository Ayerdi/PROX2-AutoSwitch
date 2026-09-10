# Documentation index

## Start here

- [README](../README.md) — product overview, installation and usage.
- [Project website](https://ayerdi.github.io/PROX2-AutoSwitch/) — visual overview and real demo/tray images.
- [English Wiki](https://github.com/Ayerdi/PROX2-AutoSwitch/wiki) — installation, behavior, tray controls, troubleshooting and FAQ.
- [Spanish Wiki](https://github.com/Ayerdi/PROX2-AutoSwitch/wiki/Inicio) — maintained Spanish user documentation.
- [Support](../SUPPORT.md) — what to include in a compatibility report.

## Technical reference

- [Maintainer guide](../AGENT.md) — verified design constraints and hardware findings.
- [Sources](../SOURCES.md) — technical references and evidence.
- [WindowsEndpointProvider](WindowsEndpointProvider.md) — historical design notes and assumptions corrected by real Bluetooth testing.
- [Security](../SECURITY.md) — trust boundaries and private reporting.

## Releases

- [Release process and definition of done](RELEASE-PROCESS.md) — reusable pre-release, publishing and public post-release validation.
- [v1.5.0 release notes](RELEASE-NOTES-v1.5.0.md)
- [v1.2.5 release notes](RELEASE-NOTES-v1.2.5.md)
- [Changelog](../CHANGELOG.md)
- [GitHub Releases](https://github.com/Ayerdi/PROX2-AutoSwitch/releases)

## Project maintenance

- [Contributing](../CONTRIBUTING.md)
- [Code of Conduct](../CODE_OF_CONDUCT.md)
- `VERSION` — single canonical stable release version.
- `scripts/check-repository.py` — repository structure/version/Wiki-link checks.
- `scripts/check-release-readiness.py` — source/package release consistency and asset validation.
- `scripts/check-language.py` — English-canonical guard outside `wiki/`.
- `scripts/build-release.sh` — deterministic release package builder.
- `scripts/publish-release.sh` — guarded local/manual publication path.
- `scripts/publish-wiki.sh` — publish the versioned bilingual Wiki source.
- `.github/workflows/release-readiness.yml` — full pre-release validation gate.
- `.github/workflows/publish-current-release.yml` — publishes only a fully validated `main` commit.
- `.github/workflows/post-release-verify.yml` — verifies the live release, checksums, Wiki and Pages.
- `.github/workflows/sync-wiki.yml` — reusable Wiki deployment.
- `scripts/configure-public-repository.sh` — apply the public GitHub settings used by this project family.
