# Release process

This project treats a release as complete only when both the repository state and the published public surfaces have been validated.

## Single source of truth

The current stable version lives in the repository-root [`VERSION`](../VERSION) file as plain `MAJOR.MINOR.PATCH`.

For a future release, for example `1.6.0`, update `VERSION` to `1.6.0` and update all release-facing content in the same pull request. CI deliberately fails if the installer, README, Wiki, Pages or release notes do not agree with `VERSION`.

The reusable workflows are not version-specific. A new release does **not** need a new publisher workflow.

## Before publishing: release-readiness

The [`release-readiness`](../.github/workflows/release-readiness.yml) workflow runs automatically when release-impacting files change and can also be started manually from GitHub Actions.

It validates:

- canonical `VERSION` syntax and cross-file version consistency;
- repository structure and required files;
- README, CHANGELOG, release notes, English/Spanish Wiki and Pages stable markers;
- the gated generic release publisher and reusable Wiki publisher;
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

## Required changes for a new version

When preparing `X.Y.Z`, the release pull request must contain at least:

1. `VERSION` set to `X.Y.Z`.
2. `CHANGELOG.md` section `## [X.Y.Z]`.
3. `docs/RELEASE-NOTES-vX.Y.Z.md` with heading `# Audio AutoSwitch vX.Y.Z`.
4. Current-version markers updated in README, Wiki EN/ES and Pages.
5. The installer-generated `config.json` version updated to `X.Y.Z`.
6. Any runtime/tests/docs changes belonging to the release.

There is no need to duplicate `release-vX.Y.Z.yml` or `wiki-vX.Y.Z.yml`. Historical one-shot workflows may remain in the repository, but new releases use the permanent generic workflows.

The readiness validator reports a concrete error for any missing or inconsistent item.

## Publishing gate

[`publish-current-release`](../.github/workflows/publish-current-release.yml) is triggered only after `release-readiness` completes successfully on `main`, or manually as a guarded recovery path.

Before creating a release it verifies that:

- the readiness result belongs to `main`;
- the validated SHA is still the current `main` SHA (a stale run cannot publish);
- manual publication has a successful `release-readiness` run for the exact same SHA;
- the release does not already exist;
- repository/source checks still pass;
- the package is rebuilt twice and remains deterministic;
- package/checksum validation passes again.

Only then does it publish exactly four assets:

```text
Audio-AutoSwitch.zip
Audio-AutoSwitch.zip.sha256
PROX2-AutoSwitch-vX.Y.Z.zip
PROX2-AutoSwitch-vX.Y.Z.zip.sha256
```

This means a release cannot be published while the Windows Pester/PSScriptAnalyzer job is still running.

The reusable [`sync-wiki`](../.github/workflows/sync-wiki.yml) workflow synchronizes `wiki/` whenever the version or Wiki source changes. The existing Pages workflow deploys `site/` and uses per-attempt artifact names so reruns do not collide.

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

## Local/manual publishing

`scripts/publish-release.sh X.Y.Z --apply` remains available for maintainers, but it is subject to the same gate: `VERSION` must match, the working tree and `main` must be exact, and both `validate` and `release-readiness` must already be green for the current SHA. It then reruns source/package checks before publishing.

## Definition of done

A stable release is considered validated when all of the following are true:

- normal `validate` is green;
- `release-readiness` is green for the release commit;
- `publish-current-release` succeeds (or reports that the exact release already exists);
- `sync-wiki` is green;
- GitHub Pages build/deploy is green;
- `post-release-verify` is green against the public release.

Hardware-specific changes still require the relevant real-device test before publication. CI proves repository/package/publication consistency; it cannot simulate every physical headset or Windows driver combination.
