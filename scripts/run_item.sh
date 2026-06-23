#!/usr/bin/env bash
#
# run_item.sh - faehrt EIN Item (alle Varianten x k Wiederholungen) durch die
# v2-Maschinerie, raeumt jeden Lauf ab und sammelt run_ids + Urteile in einem
# Item-Index. Grundlage fuer pass^k (DZ5): scripts/aggregate.py wertet die so
# erzeugten runs/<id>/manifest.json aus.
#
# Aufruf:
#   scripts/run_item.sh <scenario-id> [--k 4] [--mode agent-incluster|agent|manual]
#                       [--variants a,b] [--no-score]
#
# Standard-Mode ist agent-incluster (laptop-frei, Hauptlauf). Pro Lauf:
#   run.sh <scen> <variant> --<mode>  ->  (Agentenlauf)  ->  Urteil aus
#   agent_output.json heuristisch ziehen  ->  teardown.sh (mit/ohne --verdict).
#
# WICHTIG: Die Urteils-Extraktion ist ein VORSCHLAG. Auto-Scoring passiert nur,
# wenn die Heuristik genau ein Urteil sicher erkennt (Spalte 'sure'=yes); sonst
# wird nur abgeraeumt und der Operator vergibt das Urteil per
#   scripts/teardown.sh <run_id> --verdict <...>
# nachtraeglich (agent_output.json + transcript.jsonl bleiben erhalten).
#
# Live-Ausfuehrung nur vom Betreiber (Cluster-Zugriff). Dieses Skript fuehrt
# selbst kein kubectl aus, sondern ruft nur run.sh / teardown.sh.
#
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -ge 1 ]] || die "Aufruf: run_item.sh <scenario-id> [--k N] [--mode ...] [--variants a,b] [--no-score]"
SCENARIO="$1"; shift
K=4; MODE="agent-incluster"; VARIANTS_CSV=""; SCORE=true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --k) K="$2"; shift 2;;
    --mode) MODE="$2"; shift 2;;
    --variants) VARIANTS_CSV="$2"; shift 2;;
    --no-score) SCORE=false; shift;;
    *) die "unbekanntes Argument: $1";;
  esac
done

SCEN_DIR="$(find "$REPO_ROOT/scenarios" -maxdepth 2 -type d -name "$SCENARIO" | head -n1)"
[[ -n "$SCEN_DIR" ]] || die "Szenario nicht gefunden: $SCENARIO"

case "$MODE" in
  agent-incluster) RUN_FLAG="--agent-incluster";;
  agent)           RUN_FLAG="--agent";;
  manual)          RUN_FLAG="";;
  *) die "mode muss agent-incluster|agent|manual sein";;
esac
[[ "$MODE" != manual ]] || info "WARNUNG: mode=manual startet keinen Agenten - k-Wiederholung ohne Urteil/Scoring."

# Varianten bestimmen: explizit (--variants) oder aus scenario.yaml (variants:-Block,
# 2-Leerzeichen-eingerueckte Schluessel). variants: ist der letzte Top-Level-Block.
if [[ -n "$VARIANTS_CSV" ]]; then
  IFS=',' read -r -a VARIANTS <<< "$VARIANTS_CSV"
else
  mapfile -t VARIANTS < <(awk '
    /^variants:/{inv=1; next}
    inv && /^[^[:space:]]/{inv=0}
    inv && /^  [A-Za-z0-9_-]+:[[:space:]]*$/{ s=$0; sub(/^  /,"",s); sub(/:.*/,"",s); print s }
  ' "$SCEN_DIR/scenario.yaml")
fi
[[ ${#VARIANTS[@]} -gt 0 ]] || die "keine Varianten gefunden (scenario.yaml variants:-Block leer? sonst --variants nutzen)"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
INDEX_DIR="$REPO_ROOT/runs/_index"; mkdir -p "$INDEX_DIR"
INDEX="$INDEX_DIR/${SCENARIO}__${TS}__k${K}.tsv"
printf 'run_id\tvariant\texpected\tproposed_verdict\tsure\tscored\n' > "$INDEX"

info "Item $SCENARIO | Varianten: ${VARIANTS[*]} | k=$K | mode=$MODE | Index: $INDEX"

# --- Urteil heuristisch aus agent_output.json ziehen -> "verdict<TAB>sure" ---
# Der Agent formatiert i.d.R. einen Header "Urteil" und nennt das Verdikt erst in
# einer der folgenden Zeilen ("### 1. Urteil" \n "**nicht konform**"). Daher: ab
# der ersten Zeile mit "urteil" vorwaerts scannen und das ERSTE Verdikt-Token
# nehmen. Reihenfolge-robust: 'nicht verifizierbar' / 'nicht konform' werden vor
# blossem 'konform' geprueft. Gefunden -> sure=yes, sonst '?'/no (Operator).
extract_verdict() {
  local f="$1" txt out
  [[ -f "$f" ]] || { printf '?\tno'; return 0; }
  txt=""
  if command -v jq >/dev/null 2>&1; then txt="$(jq -r '.result // .text // empty' "$f" 2>/dev/null || true)"; fi
  [[ -n "$txt" ]] || txt="$(cat "$f" 2>/dev/null || true)"
  out="$(printf '%s' "$txt" | awk '
    BEGIN{started=0}
    { line=tolower($0)
      if(!started && line ~ /urteil/) started=1
      if(started){
        if(line ~ /nicht[ _-]*verifizierbar/){print "nicht_verifizierbar\tyes"; exit}
        if(line ~ /nicht[ _-]*konform/){print "nicht_konform\tyes"; exit}
        if(line ~ /konform/){print "konform\tyes"; exit}
      } }')"
  [[ -n "$out" ]] || out="$(printf '?\tno')"
  printf '%s' "$out"
}

PASS=0; FAIL=0; UNSURE=0; ERRORS=0
for v in "${VARIANTS[@]}"; do
  exp="$(sed -n 's/^EXPECTED_VERDICT=//p' "$SCEN_DIR/variants/$v/variant.env" 2>/dev/null | tr -d '"' | head -n1)"
  for ((i=1; i<=K; i++)); do
    info "[$SCENARIO/$v] Lauf $i/$K ..."
    rid="$("$REPO_ROOT/scripts/run.sh" "$SCENARIO" "$v" ${RUN_FLAG:+$RUN_FLAG} 2>/dev/null | tail -n1)" || rid=""
    if [[ -z "$rid" ]]; then
      info "  run.sh lieferte keine run_id (Fehler/Preflight?) - uebersprungen, Pod ggf. zur Diagnose stehen geblieben."
      ERRORS=$((ERRORS+1)); continue
    fi
    proposed="?"; sure="no"
    if [[ "$MODE" != manual ]]; then
      # extract_verdict gibt "verdict<TAB>sure" OHNE Newline aus -> read trifft EOF
      # und liefert rc=1; ohne '|| true' wuerde set -e hier abbrechen (vor Scoring/
      # teardown). Pilot-Befund 2026-06-23.
      read -r proposed sure < <(extract_verdict "$REPO_ROOT/runs/$rid/agent_output.json") || true
    fi
    scored="no"
    if [[ "$SCORE" == true && "$MODE" != manual && "$sure" == yes ]]; then
      "$REPO_ROOT/scripts/teardown.sh" "$rid" --verdict "$proposed" --notes "auto-extrahiert (run_item.sh)" >/dev/null 2>&1 || true
      scored="yes"
      if [[ "$proposed" == "$exp" ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi
    else
      "$REPO_ROOT/scripts/teardown.sh" "$rid" >/dev/null 2>&1 || true   # nur abraeumen
      [[ "$sure" == yes ]] || UNSURE=$((UNSURE+1))
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$rid" "$v" "${exp:-?}" "$proposed" "$sure" "$scored" >> "$INDEX"
  done
done

info "Fertig. auto-passed=$PASS auto-failed=$FAIL unsicher(nicht gescored)=$UNSURE laeufe_ohne_run_id=$ERRORS"
info "Auswertung: scripts/aggregate.py --requirement <REQ_ID>   (liest die manifest.json)"
info "Unsichere Urteile manuell nachtragen: scripts/teardown.sh <run_id> --verdict <...>"
echo "$INDEX"
