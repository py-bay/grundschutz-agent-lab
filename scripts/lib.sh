#!/usr/bin/env bash
# Gemeinsame Helfer fuer run.sh / teardown.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-grundschutz-lab}"
IMAGE="${IMAGE:-ubuntu:24.04}"

die() { echo "FEHLER: $*" >&2; exit 1; }
info() { echo ">> $*" >&2; }

need() { command -v "$1" >/dev/null 2>&1 || die "Werkzeug fehlt: $1"; }

sha256() {
  # Datei-Hash, plattformtolerant (Linux: sha256sum)
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}';
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

# k8s-Namen sind DNS-1123: lowercase, [a-z0-9-], <=63
sanitize() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9-]/-/g' -e 's/-\{2,\}/-/g' -e 's/^-//' -e 's/-$//' | cut -c1-50
}

# Label-Werte: [A-Za-z0-9._-], <=63, Rand alphanumerisch
label_safe() {
  echo "$1" | sed -e 's/[^A-Za-z0-9._-]/_/g' | cut -c1-63 | sed -e 's/^[._-]*//' -e 's/[._-]*$//'
}
