#!/usr/bin/env bash
#
# target-docker.sh - provisioniert das ephemere SSH-Zielsystem als LOKALEN
# Docker-Container statt als k3s-Pod. Inhaltlich identischer Bootstrap zu
# kubernetes/target-pod.tmpl.yaml (gleiches Image ubuntu:24.04, gleicher
# openssh-server-Bootstrap, gleicher audit-User, gleiche read-only sudoers-
# Whitelist, gleiche setup.sh-Etablierung des Zielzustands).
#
# Zweck: Der k3s-Cluster ist zeitweise nicht erreichbar (oeffentliche IP
# vermutlich gebannt). Fuer den explorativen DZ9-Souveraenitaets-Datenpunkt
# (opencode+Gemma lokal) laeuft das Target deshalb on-device. Bewusste,
# dokumentierte Abweichung vom Hauptlauf-Substrat (Pod -> Container); fuer
# statische Konfig-Anforderungen (z.B. SYS.1.1.A2, SYS.2.1.A18) ist ein
# bare-Container faithful (vgl. docs/lab-target-fidelity / Thesis Kap. zur
# Labor-Treue).
#
# Aufrufe:
#   target-docker.sh up   <stage_dir> <authkeys_pub> <port> <container> <image> \
#                         <variant> <ergebnisklasse> <run_id>
#   target-docker.sh down <container>
#
set -euo pipefail

cmd="${1:-}"; shift || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

target_up() {
  local stage="$1" authpub="$2" port="$3" cname="$4" image="$5" variant="$6" ek="$7" run_id="$8"
  local authdir; authdir="$(dirname "$authpub")"
  local boot="$SCRIPT_DIR/target-bootstrap.sh"
  [[ -f "$boot" ]] || { echo "FEHLER: target-bootstrap.sh fehlt: $boot" >&2; return 1; }

  # Bootstrap = inhaltlich wortgleich zum Pod-Template (target-pod.tmpl.yaml).
  # Statt es inline zu quoten, mounten wir das versionierte target-bootstrap.sh
  # read-only nach /mnt/boot. Dateiquellen sind bind-mounts (/mnt/stage,
  # /mnt/authkeys) statt ConfigMap/Secret; Anti-Leakage stellt der Bootstrap her.
  docker run -d --name "$cname" \
    --label "thesis.pybay.de/run-id=$run_id" \
    --label "thesis.pybay.de/variant=$variant" \
    --label "thesis.pybay.de/ergebnisklasse=$ek" \
    -e "RUN_ID=$run_id" \
    -p "127.0.0.1:${port}:22" \
    -v "$stage":/mnt/stage:ro \
    -v "$authdir":/mnt/authkeys:ro \
    -v "$boot":/mnt/boot/bootstrap.sh:ro \
    "$image" /bin/bash /mnt/boot/bootstrap.sh >/dev/null

  # Auf SSH-Port warten (apt install openssh-server kann dauern). Faellt der
  # Container vorher aus, brechen wir mit den Container-Logs ab.
  local i
  for i in $(seq 1 90); do
    if ! docker ps -q --filter "name=^${cname}$" | grep -q .; then
      echo "FEHLER: Target-Container '$cname' vorzeitig beendet:" >&2
      docker logs "$cname" 2>&1 | tail -20 >&2
      return 1
    fi
    if docker exec "$cname" sh -c 'pgrep -x sshd >/dev/null && [ -S /run/sshd ] 2>/dev/null || pgrep -x sshd >/dev/null' 2>/dev/null; then
      # sshd-Prozess da; Port-Bind kurz nachreifen lassen
      sleep 1; return 0
    fi
    sleep 2
  done
  echo "FEHLER: Target-Container '$cname' wurde nicht SSH-bereit (Timeout). Logs:" >&2
  docker logs "$cname" 2>&1 | tail -20 >&2
  return 1
}

target_down() {
  local cname="$1"
  docker rm -f "$cname" >/dev/null 2>&1 || true
}

case "$cmd" in
  up)   target_up "$@";;
  down) target_down "$@";;
  *) echo "Aufruf: target-docker.sh up <stage> <authpub> <port> <container> <image> <variant> <ek> <run_id> | down <container>" >&2; exit 1;;
esac
