# Release process

This project treats a release as complete only when both the repository state and the published public surfaces have been validated.

## Single source of truth

The current stable version lives in the repository-root [`VERSION`](../VERSION) file as plain `MAJOR.MINOR.PATCH`.

For a future release, for example `1.6.0`, update `VERSION` to `1.6.0` and update all release-facing content in the same pull request. CI deliberately fails if the installer, README, Wiki, Pages, release notes or versioned publisher do not agree with `VERSION`.

## Before publishing: release-readiness

The [`release-readiness`](../.github/workflows/release-readiness.yml) workflow runs automatically when release-impacting files change and can also be started manually from GitHub Actions.

It validates:

- canonical `VERSION` syntax and cross-file version consistency;
- repository structure and required files;
- README, CHANGELOG, release notes, English/Spanish Wiki and Pages stable markers;
- the versioned release publisher and Wiki publisher for the target version;
- GitHub Pages rerun safety;
- English canonical-language policy and Wiki links;
- Bash syntax and Git whitespace;
- gitleaks secret scanning;
- PowerShell parser validation;
- PSScriptAnalyzer warnings/errors;
- the full Pester suite;
- two independent deterministic release builds;
- byte equality between the versioned ZIP and `Audio-AutoSwitch.zip`;
- SHA-256 files and asset names;
- ZIP path safety and critical package contents;
- packaged README/CHANGELOG version consistency.

The aggregate `release-readiness` job is green only when every component succeeds.

## Required files for a new version

When preparing `X.Y.Z`, the release pull request must contain at least:

1. `VERSION` set to `X.Y.Z`.
2. `CHANGELOG.md` section `## [X.Y.Z]`.
3. `docs/RELEASE-NOTES-vX.Y.Z.md` with heading `# Audio AutoSwitch vX.Y.Z`.
4. `.github/workflows/release-vX.Y.Z.yml`.
5. `.github/workflows/wiki-vX.Y.Z.yml`.
6. Current-version markers updated in README, Wiki EN/ES and Pages.
7. The installer-generated `config.json` version updated to `X.Y.Z`.
8. Any runtime/tests/docs changes belonging to the release.

The readiness validator reports a concrete error for any missing or inconsistent item.

## Publishing

After the release pull request is green and merged into `main`:

- the versioned release workflow builds the package twice and publishes exactly four assets;
- the versioned Wiki workflow synchronizes `wiki/` to the public GitHub Wiki;
- the Pages workflow deploys `site/`;
- normal `validate` runs again on `main`.

Expected release assets:

```text
Audio-AutoSwitch.zip
Audio-AutoSwitch.zip.sha256
PROX2-AutoSwitch-vX.Y.Z.zip
PROX2-AutoSwitch-vX.Y.Z.zip.sha256
```

## After publishing: post-release-verify

The [`post-release-verify`](../.github/workflows/post-release-verify.yml) workflow runs whenever a GitHub Release is published and can also be started manually.

It verifies the actual public result rather than only source files:

- the release exists and is neither draft nor prerelease;
- it is the latest stable release;
- exactly the four expected assets exist;
- both checksum files match the downloaded ZIPs;
- both ZIP aliases are byte-identical;
- the downloaded package passes the same package inspector used before release;
- the public English Wiki reports the current version;
- the public Spanish Wiki reports the current version;
- the deployed GitHub Pages site reports the current version.

The public checks retry briefly because GitHub Release assets, Wiki and Pages can propagate asynchronously.

## Definition of done

A stable release is considered validated when all of the following are true:

- normal `validate` is green;
- `release-readiness` is green for the release commit;
- the versioned release and Wiki workflows are green;
- GitHub Pages build/deploy is green;
- `post-release-verify` is green against the public release.

Hardware-specific changes still require the relevant real-device test before publication. CI proves repository/package/publication consistency; it cannot simulate every physical headset or Windows driver combination.
