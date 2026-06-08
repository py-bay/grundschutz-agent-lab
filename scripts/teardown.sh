#!/usr/bin/env bash
#
# teardown.sh - raeumt einen Lauf ab und schreibt das Agentenurteil ins
# Manifest. Berechnet agent.passed = (Urteil == erwartetes Urteil).
#
# Aufruf:
#   scripts/teardown.sh <run_id> [--verdict konform|nicht_konform] [--notes "..."] [--keep]
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
    konform) AGENT_COMPLIANT=true;;
    nicht_konform|nicht-konform) AGENT_COMPLIANT=false;;
    *) die "verdict muss konform|nicht_konform sein";;
  esac
  EXPECTED="$(sed -n 's/.*"expected_compliant":[[:space:]]*\(true\|false\).*/\1/p' "$MANIFEST" | head -n1)"
  if [[ "$AGENT_COMPLIANT" == "$EXPECTED" ]]; then PASSED=true; else PASSED=false; fi
  ENDED="$(date -u +%Y%m%dT%H%M%SZ)"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$MANIFEST" "$AGENT_COMPLIANT" "$PASSED" "$NOTES" "$ENDED" <<'PY'
import json,sys
m,verdict,passed,notes,ended=sys.argv[1:6]
d=json.load(open(m))
d["phase"]="done"
d["agent"]={"verdict":(verdict=="true"),"passed":(passed=="true"),"notes":notes or None,"ended_utc":ended}
json.dump(d,open(m,"w"),indent=2,ensure_ascii=False)
PY
  else
    info "python3 fehlt - Manifest bitte manuell ergaenzen (agent.verdict/passed)."
  fi
  info "Urteil: $VERDICT (compliant=$AGENT_COMPLIANT) | erwartet=$EXPECTED | passed=$PASSED"
fi

# Cluster-Objekte loeschen (Pod laeuft nicht weiter)
if [[ "$KEEP" == false ]]; then
  jget() { sed -n "s/.*\"$1\":[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$MANIFEST" | head -n1; }
  POD="$(jget pod_name)"; LABEL="$(jget run_id_label)"
  [[ -n "$LABEL" ]] || LABEL="$(label_safe "$RUN_ID")"
  $KUBECTL -n "$NAMESPACE" delete pod "$POD" --ignore-not-found >/dev/null 2>&1 || true
  $KUBECTL -n "$NAMESPACE" delete configmap,secret -l "thesis.pybay.de/run-id=$LABEL" --ignore-not-found >/dev/null 2>&1 || true
  info "Pod $POD abgeraeumt (ConfigMap/Secret ueber Label run-id=$LABEL)."
else
  info "Pod bleibt stehen (--keep)."
fi

info "Manifest: $MANIFEST"
