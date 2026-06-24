#!/usr/bin/env bash
# Gemeinsame Helfer fuer run.sh / teardown.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-grundschutz-lab}"
IMAGE="${IMAGE:-ubuntu:24.04}"
# Pruefagent-Image (in-cluster, --agent-incluster). Aus der Forgejo-OCI-Registry.
# Vor dem Hauptlauf per Digest pinnen (siehe images/claude-code/Dockerfile).
AGENT_IMAGE="${AGENT_IMAGE:-git.k3s.pybay.de/gitsim/claude-code:latest}"
# Modell des Pruefagenten (DZ5/DZ9: versionierter, gepinnter Parameter). Leer =
# claude-CLI-Default (NICHT reproduzierbar, im Pilot ein Sonnet/Haiku-Mix). Fuer
# den Hauptlauf pinnen, z.B. AGENT_MODEL=claude-opus-4-8 (s. images/PINNING.md).
AGENT_MODEL="${AGENT_MODEL:-}"
# Reasoning-Effort des Pruefagenten (DZ5: dokumentierter, gepinnter Parameter).
# Im Entrypoint als 'claude -p --effort' gesetzt. Stufen: low|medium|high|xhigh|max.
# Hauptlauf-Setzung: high (Claude-Code-Default fuer Opus 4.8).
AGENT_EFFORT="${AGENT_EFFORT:-high}"

# kubectl-Aufruf: auf dem Laptop "kubectl" (braucht KUBECONFIG/Tunnel),
# direkt auf dem k3s-Node "k3s kubectl" (nutzt /etc/rancher/k3s/k3s.yaml
# automatisch, kein Tunnel noetig). Override per KUBECTL=... moeglich.
if [[ -z "${KUBECTL:-}" ]]; then
  if command -v kubectl >/dev/null 2>&1; then KUBECTL="kubectl"
  elif command -v k3s >/dev/null 2>&1; then KUBECTL="k3s kubectl"
  else KUBECTL="kubectl"; fi
fi

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
