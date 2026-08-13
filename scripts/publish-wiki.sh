#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REPOSITORY="${AUTOSWITCH_GITHUB_REPOSITORY:-Ayerdi/PROX2-AutoSwitch}"
APPLY="${1:-}"

if [[ "${APPLY}" != "--apply" || $# -ne 1 ]]; then
  printf 'Usage: %s --apply\n' "$0" >&2
  exit 2
fi

command -v gh >/dev/null || { printf 'GitHub CLI (gh) is required.\n' >&2; exit 1; }
command -v git >/dev/null || { printf 'git is required.\n' >&2; exit 1; }
cd "${ROOT_DIR}"

gh auth status >/dev/null 2>&1 || { printf 'GitHub CLI has no valid session. Run gh auth login.\n' >&2; exit 1; }
[[ -z "$(git status --short)" ]] || { printf 'The Git tree must be clean before publishing the Wiki.\n' >&2; exit 1; }
[[ "$(git branch --show-current)" == "main" ]] || { printf 'Publish the Wiki only from main.\n' >&2; exit 1; }

git fetch --quiet origin main
head_sha="$(git rev-parse HEAD)"
remote_sha="$(git rev-parse origin/main)"
[[ "${head_sha}" == "${remote_sha}" ]] || { printf 'HEAD does not match origin/main. Update the checkout.\n' >&2; exit 1; }

visibility="$(gh repo view "${REPOSITORY}" --json visibility --jq .visibility)"
[[ "${visibility}" == "PUBLIC" ]] || { printf 'The repository must be public before publishing the Wiki.\n' >&2; exit 1; }
wiki_enabled="$(gh repo view "${REPOSITORY}" --json hasWikiEnabled --jq .hasWikiEnabled)"
[[ "${wiki_enabled}" == "true" ]] || { printf 'GitHub Wiki is not enabled for %s.\n' "${REPOSITORY}" >&2; exit 1; }

python3 scripts/check-repository.py
python3 scripts/check-language.py

tmp="$(mktemp -d /tmp/autoswitch-wiki.XXXXXX)"
trap 'rm -rf -- "${tmp}"' EXIT

gh auth setup-git >/dev/null
if ! git clone --quiet "https://github.com/${REPOSITORY}.wiki.git" "${tmp}/wiki"; then
  printf 'The GitHub Wiki repository is not initialized yet. Create the first Home page in the GitHub Wiki UI, then rerun this command.\n' >&2
  exit 1
fi

find "${tmp}/wiki" -mindepth 1 -maxdepth 1 -type f -name '*.md' -delete
cp "${ROOT_DIR}"/wiki/*.md "${tmp}/wiki/"
cd "${tmp}/wiki"
git add --all
if git diff --cached --quiet; then
  printf 'Wiki is already synchronized with main %s.\n' "${head_sha}"
  exit 0
fi

git config user.name "Ayerdi"
git config user.email "128999164+Ayerdi@users.noreply.github.com"
git commit -m "docs: sync Wiki from repository main ${head_sha}" >/dev/null
git push --quiet origin master 2>/dev/null || git push --quiet origin main
printf 'Wiki synchronized from repository main %s.\n' "${head_sha}"
