#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION='8.24.3'
case "$(uname -m)" in
  x86_64|amd64) ARCH='x64'; SHA='9991e0b2903da4c8f6122b5c3186448b927a5da4deef1fe45271c3793f4ee29c' ;;
  aarch64|arm64) ARCH='arm64'; SHA='5f2edbe1f49f7b920f9e06e90759947d3c5dfc16f752fb93aaafc17e9d14cf07' ;;
  *) printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2; exit 2 ;;
esac
TMP="$(mktemp -d /tmp/autoswitch-gitleaks.XXXXXX)"; trap 'rm -rf -- "${TMP}"' EXIT
ARCHIVE="${TMP}/gitleaks.tar.gz"
curl --fail --silent --show-error --location --output "${ARCHIVE}" "https://github.com/gitleaks/gitleaks/releases/download/v${VERSION}/gitleaks_${VERSION}_linux_${ARCH}.tar.gz"
printf '%s  %s\n' "${SHA}" "${ARCHIVE}" | sha256sum --check --status
tar --extract --gzip --file "${ARCHIVE}" --directory "${TMP}" gitleaks
"${TMP}/gitleaks" detect --source "${ROOT_DIR}" --redact --no-banner
