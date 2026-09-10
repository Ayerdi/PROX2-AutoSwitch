#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REPOSITORY="${AUTOSWITCH_GITHUB_REPOSITORY:-Ayerdi/PROX2-AutoSwitch}"
VERSION="${1:-}"
APPLY="${2:-}"

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || "${APPLY}" != "--apply" || $# -ne 2 ]]; then
  printf 'Usage: %s MAJOR.MINOR.PATCH --apply\n' "$0" >&2
  exit 2
fi

canonical_version="$(tr -d '\r\n' < "${ROOT_DIR}/VERSION")"
[[ "${VERSION}" == "${canonical_version}" ]] || {
  printf 'Requested release %s does not match canonical VERSION %s.\n' "${VERSION}" "${canonical_version}" >&2
  exit 1
}

command -v gh >/dev/null || { printf 'GitHub CLI (gh) is required.\n' >&2; exit 1; }
command -v git >/dev/null || { printf 'git is required.\n' >&2; exit 1; }
cd "${ROOT_DIR}"

gh auth status >/dev/null 2>&1 || { printf 'GitHub CLI has no valid session. Run gh auth login.\n' >&2; exit 1; }
[[ -z "$(git status --short)" ]] || { printf 'The Git tree must be clean.\n' >&2; exit 1; }
[[ "$(git branch --show-current)" == "main" ]] || { printf 'Stable releases can only be published from main.\n' >&2; exit 1; }

git fetch --quiet origin main --tags
head_sha="$(git rev-parse HEAD)"
remote_sha="$(git rev-parse origin/main)"
[[ "${head_sha}" == "${remote_sha}" ]] || { printf 'HEAD does not match origin/main. Update the checkout.\n' >&2; exit 1; }

workflow_state() {
  local workflow="$1"
  gh run list \
    --repo "${REPOSITORY}" \
    --workflow "${workflow}" \
    --branch main \
    --limit 1 \
    --json headSha,status,conclusion \
    --jq '.[0] | (.headSha // "") + ":" + (.status // "") + ":" + (.conclusion // "")'
}

ci_state="$(workflow_state validate.yml)"
[[ "${ci_state}" == "${head_sha}:completed:success" ]] || {
  printf 'Validation is not green for HEAD %s (%s).\n' "${head_sha}" "${ci_state:-no run}" >&2
  exit 1
}

readiness_state="$(workflow_state release-readiness.yml)"
[[ "${readiness_state}" == "${head_sha}:completed:success" ]] || {
  printf 'Release readiness is not green for HEAD %s (%s).\n' "${head_sha}" "${readiness_state:-no run}" >&2
  exit 1
}

notes="docs/RELEASE-NOTES-v${VERSION}.md"
[[ -f "${notes}" ]] || { printf 'Missing release notes: %s\n' "${notes}" >&2; exit 1; }
grep -Fq "## [${VERSION}]" CHANGELOG.md || { printf 'CHANGELOG.md does not contain version %s.\n' "${VERSION}" >&2; exit 1; }

if gh release view "v${VERSION}" --repo "${REPOSITORY}" >/dev/null 2>&1; then
  printf 'Release v%s already exists; it will not be overwritten.\n' "${VERSION}" >&2
  exit 1
fi

python3 scripts/check-repository.py
python3 scripts/check-language.py
bash scripts/run-gitleaks.sh
python3 scripts/check-release-readiness.py --version "${VERSION}" --source-only

bash scripts/build-release.sh "${VERSION}"
archive="dist/PROX2-AutoSwitch-v${VERSION}.zip"
checksum="${archive}.sha256"
first="$(cut -d' ' -f1 "${checksum}")"
first_copy="$(mktemp /tmp/autoswitch-release.XXXXXX.zip)"
trap 'rm -f -- "${first_copy}"' EXIT
cp "${archive}" "${first_copy}"
rm -f dist/*.zip dist/*.sha256
bash scripts/build-release.sh "${VERSION}"
second="$(cut -d' ' -f1 "${checksum}")"
test "${first}" = "${second}"
cmp "${first_copy}" "${archive}"
cmp "${archive}" dist/Audio-AutoSwitch.zip
python3 scripts/check-release-readiness.py --version "${VERSION}" --package-only

gh release create "v${VERSION}" \
  "${archive}" "${checksum}" \
  dist/Audio-AutoSwitch.zip dist/Audio-AutoSwitch.zip.sha256 \
  --repo "${REPOSITORY}" \
  --target "${head_sha}" \
  --title "v${VERSION}" \
  --notes-file "${notes}"

uploaded_digest="$(gh api "repos/${REPOSITORY}/releases/tags/v${VERSION}" --jq ".assets[] | select(.name == \"$(basename "${archive}")\") | (.digest // \"\")")"
[[ "${uploaded_digest}" == "sha256:${second}" ]] || { printf 'GitHub returned an unexpected archive digest: %s\n' "${uploaded_digest:-empty}" >&2; exit 1; }

printf 'Release v%s published from fully validated commit %s.\n' "${VERSION}" "${head_sha}"
printf 'Published digest: %s\n' "${uploaded_digest}"
