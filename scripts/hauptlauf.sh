#!/usr/bin/env bash
#
# hauptlauf.sh - summativer k=4-Hauptlauf ueber die sauberen, live agent-
# validierten Traeger (Runde 2). Ruft run_item.sh je Item (alle Varianten x k).
#
# VOR dem Lauf (siehe docs/hauptlauf-runbook.md):
#   - SSH-Tunnel zum API-Server steht (kubectl get nodes -> beide Ready),
#   - Modell gepinnt:  export AGENT_MODEL=claude-opus-4-8   (DZ5/DZ9!),
#   - optional Images per Digest gepinnt (export IMAGE=... AGENT_IMAGE=...,
#     images/PINNING.md),
#   - Szenarien eingefroren/committet (GT-Hashes stehen pro Lauf im Manifest).
#
# Laeuft lange (~40 Laeufe x ~4 min ~ 2-3 h). Sinnvoll im Hintergrund fahren und
# stueckweise monitoren. Auswertung danach: scripts/aggregate.py.
#
# Aufruf:  [AGENT_MODEL=...] scripts/hauptlauf.sh [k]      (Default k=4)
#
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

K="${1:-4}"

# Saubere, agent-validierte Traeger ueber den Ergebnisraum (EK1-5). A19 ist ein
# EK5-Befund (keine saubere Abstinenz) und absichtlich NICHT enthalten; bei Bedarf
# A19/SYS.2.3.A1 als dokumentierte Befund-Traeger separat fahren.
ITEMS=(
  SYS.2.1.A18-ssh-crypto-strength       # EK1 + EK2 (Sachurteil-Paar)
  SYS.1.1.A33-trust-store-baseline      # EK3 (Trust-Store-Synthese)
  SYS.1.1.A2-authpolicy-synthesis       # EK3 (PAM/pwquality-Synthese)
  SYS.1.1.A2-shadow-hash-rootonly       # EK4 (Abstinenz, gegatete Evidenz)
  SYS.1.1.A39-central-mgmt-offhost      # EK5 (Abstinenz, off-host)
)

info "=== HAUPTLAUF  k=$K  Items=${#ITEMS[@]} ==="
info "Modell : ${AGENT_MODEL:-<CLI-DEFAULT!>}"
info "Image  : Target=${IMAGE}  Agent=${AGENT_IMAGE}"
if [[ -z "${AGENT_MODEL:-}" ]]; then
  info "WARNUNG: AGENT_MODEL nicht gesetzt -> CLI-Default-Modell (im Pilot Sonnet/Haiku-Mix),"
  info "         NICHT reproduzierbar/Thesis-konform. Mit Ctrl-C abbrechen und AGENT_MODEL pinnen."
  sleep 5
fi

# Tunnel-/Cluster-Check
$KUBECTL get nodes >/dev/null 2>&1 || die "Cluster nicht erreichbar (SSH-Tunnel? kubectl get nodes)."
for s in claude-oauth otel-auth forgejo-pull; do
  $KUBECTL -n "$NAMESPACE" get secret "$s" >/dev/null 2>&1 || die "Secret '$s' fehlt im NS $NAMESPACE."
done

fail=0
for it in "${ITEMS[@]}"; do
  info "----- Item $it (k=$K) -----"
  "$REPO_ROOT/scripts/run_item.sh" "$it" --k "$K" --mode agent-incluster || { info "Item $it mit Fehlern."; fail=1; }
done

info "=== Hauptlauf fertig (fail=$fail). Auswertung: ==="
info "  scripts/aggregate.py --json runs/_index/hauptlauf.json"
[[ $fail -eq 0 ]] || info "Einige Items hatten Fehler - run_item-Indizes + manifest.json pruefen."
