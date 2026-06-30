#!/usr/bin/env bash
#
# teardown.sh - raeumt einen Lauf ab und schreibt das Agentenurteil ins
# Manifest. Berechnet agent.passed = (Urteil == expected_verdict).
#
# Schema v2: dreiwertiges Urteil konform|nicht_konform|nicht_verifizierbar.
# Die klassenabhaengige Wertungsregel (nicht_verifizierbar = korrektes Soll in
# Ergebnisklassen 4/5, sonst nicht bestanden) ist hier bereits aufgeloest, weil
# expected_verdict pro Variante pre-committed ist.
#
# Aufruf:
#   scripts/teardown.sh <run_id> [--verdict konform|nicht_konform|nicht_verifizierbar] [--notes "..."] [--keep]
#
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -ge 1 ]] || die "Aufruf: teardown.sh <run_id> [--verdict ...] [--notes ...] [--keep]"
RUN_ID="$1"; shift
VERDICT=""; NOTES=""; KEEP=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --verdict) VERDICT="$2"; shift 2;;
    --notes) NOTES="$2"; shift 2;;
    --keep) KEEP=true; shift;;
    *) die "unbekanntes Argument: $1";;
  esac
done

RUN_DIR="$REPO_ROOT/runs/$RUN_ID"
[[ -d "$RUN_DIR" ]] || die "Lauf nicht gefunden: $RUN_DIR"
MANIFEST="$RUN_DIR/manifest.json"

# Port-Forward beenden
if [[ -f "$RUN_DIR/portforward.pid" ]]; then
  kill "$(cat "$RUN_DIR/portforward.pid")" 2>/dev/null || true
  rm -f "$RUN_DIR/portforward.pid"
fi

# Urteil verrechnen
if [[ -n "$VERDICT" ]]; then
  case "$VERDICT" in
    konform|nicht_konform|nicht-konform|nicht_verifizierbar|nicht-verifizierbar) :;;
    *) die "verdict muss konform|nicht_konform|nicht_verifizierbar sein";;
  esac
  VERDICT="${VERDICT//-/_}"   # nicht-konform -> nicht_konform
  EXPECTED="$(sed -n 's/.*"expected_verdict":[[:space:]]*"\([^"]*\)".*/\1/p' "$MANIFEST" | head -n1)"
  [[ -n "$EXPECTED" ]] || die "expected_verdict fehlt im Manifest (alter A8-Lauf? dort expected_compliant)"
  if [[ "$VERDICT" == "$EXPECTED" ]]; then PASSED=true; else PASSED=false; fi
  ENDED="$(date -u +%Y%m%dT%H%M%SZ)"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$MANIFEST" "$VERDICT" "$PASSED" "$NOTES" "$ENDED" <<'PY'
import json,sys
m,verdict,passed,notes,ended=sys.argv[1:6]
d=json.load(open(m))
d["phase"]="done"
d["agent"]={"verdict":verdict,"passed":(passed=="true"),"notes":notes or None,"ended_utc":ended}
json.dump(d,open(m,"w"),indent=2,ensure_ascii=False)
PY
  else
    info "python3 fehlt - Manifest bitte manuell ergaenzen (agent.verdict/passed)."
  fi
  info "Urteil: $VERDICT | erwartet=$EXPECTED | passed=$PASSED"
fi

# Ziel-Objekte loeschen (Target laeuft nicht weiter)
jget() { sed -n "s/.*\"$1\":[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$MANIFEST" | head -n1; }
TARGET="$(jget target)"; [[ -n "$TARGET" ]] || TARGET="k8s"   # alte Manifeste = k8s
if [[ "$KEEP" == false ]]; then
  if [[ "$TARGET" == docker ]]; then
    CONTAINER="$(jget container_name)"
    [[ -n "$CONTAINER" ]] || CONTAINER="lab-target-$(label_safe "$RUN_ID")"
    "$REPO_ROOT/scripts/target-docker.sh" down "$CONTAINER" || true
    info "Lauf-Objekte abgeraeumt (docker-Target $CONTAINER entfernt)."
  else
    POD="$(jget pod_name)"; LABEL="$(jget run_id_label)"
    [[ -n "$LABEL" ]] || LABEL="$(label_safe "$RUN_ID")"
    $KUBECTL -n "$NAMESPACE" delete pod "$POD" --ignore-not-found >/dev/null 2>&1 || true
    # Alle laufbezogenen Objekte ueber das run-id-Label: Target-Pod, Agent-Job
    # (+ dessen Pods), Target-Service, Szenario-/Prompt-ConfigMaps, Key-/Auth-Secrets.
    $KUBECTL -n "$NAMESPACE" delete pod,job,service,configmap,secret \
      -l "thesis.pybay.de/run-id=$LABEL" --ignore-not-found >/dev/null 2>&1 || true
    info "Lauf-Objekte abgeraeumt (Pod/Job/Service/ConfigMap/Secret ueber Label run-id=$LABEL)."
  fi
else
  info "Target bleibt stehen (--keep)."
fi

info "Manifest: $MANIFEST"
