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
[[ -z "$(git status --short)" ]] || { printf 'The Git tree must be clean.\n' >&2; exit 1; }
[[ "$(git branch --show-current)" == "main" ]] || { printf 'Run repository configuration from main.\n' >&2; exit 1; }

git fetch --quiet origin main
head_sha="$(git rev-parse HEAD)"
[[ "${head_sha}" == "$(git rev-parse origin/main)" ]] || { printf 'HEAD does not match origin/main. Update the checkout.\n' >&2; exit 1; }

visibility="$(gh repo view "${REPOSITORY}" --json visibility --jq .visibility)"
[[ "${visibility}" == "PUBLIC" ]] || { printf 'The repository must already be public.\n' >&2; exit 1; }

python3 scripts/check-repository.py
python3 scripts/check-language.py

gh api --method PATCH "repos/${REPOSITORY}" \
  -f description='Automatic Windows audio output switching for compatible wireless headsets, with a Logitech PRO X 2 fallback.' \
  -f homepage='https://ayerdi.github.io/PROX2-AutoSwitch/' \
  -F has_issues=true \
  -F has_discussions=true \
  -F has_wiki=true \
  -F delete_branch_on_merge=true >/dev/null

gh api --method PUT "repos/${REPOSITORY}/topics" \
  -f 'names[]=windows' \
  -f 'names[]=audio' \
  -f 'names[]=headset' \
  -f 'names[]=powershell' \
  -f 'names[]=logitech' \
  -f 'names[]=automation' \
  -f 'names[]=open-source' >/dev/null

gh api --method PUT "repos/${REPOSITORY}/vulnerability-alerts" >/dev/null || true
gh api --method PUT "repos/${REPOSITORY}/private-vulnerability-reporting" >/dev/null || true

gh api --method PUT "repos/${REPOSITORY}/branches/main/protection" \
  -H 'Accept: application/vnd.github+json' \
  -f required_status_checks[strict]=true \
  -f 'required_status_checks[contexts][]=quality' \
  -f 'required_status_checks[contexts][]=powershell' \
  -f 'required_status_checks[contexts][]=secrets' \
  -F enforce_admins=true \
  -f required_pull_request_reviews[dismiss_stale_reviews]=false \
  -F required_pull_request_reviews[required_approving_review_count]=0 \
  -F restrictions= \
  -F required_conversation_resolution=true \
  -F allow_force_pushes=false \
  -F allow_deletions=false >/dev/null

if gh api "repos/${REPOSITORY}/pages" >/dev/null 2>&1; then
  gh api --method PUT "repos/${REPOSITORY}/pages" -f build_type=workflow >/dev/null
else
  gh api --method POST "repos/${REPOSITORY}/pages" -f build_type=workflow >/dev/null
fi

gh workflow run pages.yml --repo "${REPOSITORY}"
printf 'Public repository settings applied. Publish the versioned Wiki with scripts/publish-wiki.sh --apply.\n'
