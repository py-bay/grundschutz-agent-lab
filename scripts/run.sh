#!/usr/bin/env bash
#
# run.sh - zieht EIN ephemeres SSH-Zielsystem fuer einen Lab-Lauf hoch,
# schreibt ein pre-committed Run-Manifest und oeffnet einen Port-Forward.
# Der Pod laeuft NICHT dauerhaft: teardown.sh raeumt ihn wieder ab.
#
# Schema v2 (Coverage-Design, dreiwertig):
#   - Variante = inszenierter Zielzustand (variants/<v>/setup.sh + variant.env),
#     nicht mehr nur eine sshd_config. Variantennamen sind szenario-definiert.
#   - Urteil dreiwertig: expected_verdict konform|nicht_konform|nicht_verifizierbar.
#   - sudoers (read-only Kommando-Whitelist) kommt pro Szenario aus <scen>/sudoers.
# Abwaertskompatibel: Szenarien mit nur variants/<v>/sshd_config (A8-Durchstich)
# laufen ueber einen Legacy-Zweig unveraendert weiter.
#
# Aufruf:
#   scripts/run.sh <scenario-id> <variant> [--port 12222] [--agent]
#
# Voraussetzungen auf dem Betreiber-Laptop:
#   - kubectl mit gueltiger kubeconfig (ggf. via SSH-Tunnel zum API-Server)
#   - envsubst (gettext), openssl, ssh-keygen
#
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -ge 2 ]] || die "Aufruf: run.sh <scenario-id> <variant> [--port N] [--agent]"
SCENARIO="$1"; VARIANT="$2"; shift 2
# Default-Port bewusst NICHT 2222: dort lauscht auf dem Node oft Forgejos
# eingebauter Go-SSH-Server -> Kollision (Agent landet auf Forgejo statt Pod).
PORT=12222
RUN_AGENT=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2;;
    --agent) RUN_AGENT=true; shift;;       # claude direkt fahren + Output pro Lauf sichern
    *) die "unbekanntes Argument: $1";;
  esac
done

need envsubst; need openssl; need ssh-keygen
info "kubectl: $KUBECTL"

# Szenario aufloesen (unter scenarios/*/<id>/)
SCEN_DIR="$(find "$REPO_ROOT/scenarios" -maxdepth 2 -type d -name "$SCENARIO" | head -n1)"
[[ -n "$SCEN_DIR" ]] || die "Szenario nicht gefunden: $SCENARIO"
VAR_DIR="$SCEN_DIR/variants/$VARIANT"
GT_SRC="$SCEN_DIR/ground_truth.md"
[[ -d "$VAR_DIR" ]] || die "Variante nicht gefunden: $VAR_DIR"
[[ -f "$GT_SRC" ]] || die "ground_truth.md fehlt: $GT_SRC"

# flacher scenario.yaml-Skalar, Inline-Kommentar (# ...) + Rand-Whitespace gestrippt
yval() { sed -n "s/^$1:[[:space:]]*//p" "$SCEN_DIR/scenario.yaml" | head -n1 | sed -e 's/[[:space:]]*#.*$//' -e 's/[[:space:]]*$//'; }
REQ_ID="$(yval requirement_id)"
MODULE_ID="$(yval module)"
CATEGORY="$(yval category)"
CELL="$(yval cell)"
[[ -n "$REQ_ID" ]] || REQ_ID="$SCENARIO"
[[ -n "$CATEGORY" ]] || CATEGORY="A"
[[ -n "$CELL" ]] || CELL="-"

# --- Staging: genau die Dateien zusammenstellen, die in den Pod gemountet werden ---
TS="$(date -u +%Y%m%dT%H%M%SZ)"
RAND="$(openssl rand -hex 3)"
RUN_ID="${REQ_ID}__${VARIANT}__${TS}__${RAND}"
RUN_DIR="$REPO_ROOT/runs/$RUN_ID"
STAGE="$RUN_DIR/stage"
mkdir -p "$RUN_DIR/ssh" "$STAGE"

if [[ -f "$VAR_DIR/setup.sh" ]]; then
  # v2: vollstaendiges Varianten-Verzeichnis (setup.sh + ggf. weitere Artefakte)
  cp "$VAR_DIR"/* "$STAGE"/ 2>/dev/null || true
  rm -f "$STAGE/variant.env"        # host-seitige Metadaten nicht in den Pod mounten
  EXPECTED_VERDICT="$(sed -n 's/^EXPECTED_VERDICT=//p' "$VAR_DIR/variant.env" 2>/dev/null | tr -d '"' | head -n1)"
else
  # Legacy (A8-Durchstich): nur sshd_config, setup.sh wird hier synthetisiert
  [[ -f "$VAR_DIR/sshd_config" ]] || die "weder setup.sh noch sshd_config in $VAR_DIR"
  cp "$VAR_DIR/sshd_config" "$STAGE/sshd_config"
  cat > "$STAGE/setup.sh" <<'LEGACY'
#!/usr/bin/env bash
set -euo pipefail
cp /etc/thesis/sshd_config /etc/ssh/sshd_config
chmod 644 /etc/ssh/sshd_config
LEGACY
  case "$VARIANT" in
    compliant) EXPECTED_VERDICT="konform";;
    non_compliant) EXPECTED_VERDICT="nicht_konform";;
    *) EXPECTED_VERDICT="";;
  esac
fi
[[ -n "$EXPECTED_VERDICT" ]] || die "EXPECTED_VERDICT unbestimmt (variant.env fehlt?)"
case "$EXPECTED_VERDICT" in
  konform) EXPECTED_COMPLIANT=true;;
  nicht_konform) EXPECTED_COMPLIANT=false;;
  nicht_verifizierbar) EXPECTED_COMPLIANT=null;;
  *) die "expected_verdict ungueltig: $EXPECTED_VERDICT";;
esac

# sudoers (read-only Kommando-Whitelist) pro Szenario; Legacy-Default = sshd -T
if [[ -f "$SCEN_DIR/sudoers" ]]; then
  cp "$SCEN_DIR/sudoers" "$STAGE/audit_sudoers"
else
  printf 'audit ALL=(root) NOPASSWD: /usr/sbin/sshd -T\n' > "$STAGE/audit_sudoers"
fi

# --- Run-Identitaet + Provenance (Hashes stehen VOR dem Agentenlauf fest) ---
GT_HASH="$(sha256 "$GT_SRC")"
SUDOERS_HASH="$(sha256 "$STAGE/audit_sudoers")"
# Zustands-Hash ueber alle gemounteten Szenario-Dateien, reihenfolgestabil
STATE_HASH="$(find "$STAGE" -type f -exec sha256sum {} + | awk '{print $1}' | sort | sha256sum | awk '{print $1}')"

# Ephemeres Schluesselpaar fuer genau diesen Lauf (privater Key bleibt lokal)
ssh-keygen -t ed25519 -N "" -C "audit@$RUN_ID" -f "$RUN_DIR/ssh/id_ed25519" >/dev/null

POD_NAME="target-$(sanitize "${VARIANT}-${RAND}")"
CM_NAME="scenario-$(sanitize "${VARIANT}-${RAND}")"
SECRET_NAME="authkeys-$(sanitize "${VARIANT}-${RAND}")"
RUN_ID_LABEL="$(label_safe "$RUN_ID")"
REQ_ID_LABEL="$(label_safe "$REQ_ID")"
VARIANT_LABEL="$(label_safe "$VARIANT")"
CELL_LABEL="$(label_safe "$CELL")"

# OTEL-Resource-Attribute (keine Leerzeichen erlaubt) -> taggt jede
# Claude-Code-Metrik/jedes Event mit run.id, in OpenObserve pro Lauf abfragbar
OTEL_ATTRS="run.id=${RUN_ID},scenario=${SCENARIO},variant=${VARIANT},requirement.id=${REQ_ID},cell=${CELL}"

info "Run-ID: $RUN_ID"
info "Kategorie/Zelle: $CATEGORY / $CELL | erwartetes Urteil: $EXPECTED_VERDICT"
info "Namespace/Pod: $NAMESPACE/$POD_NAME (node role=lab)"

# --- Cluster-Objekte erzeugen ---
$KUBECTL apply -f "$REPO_ROOT/kubernetes/namespace.yaml" >/dev/null
$KUBECTL -n "$NAMESPACE" create configmap "$CM_NAME" --from-file="$STAGE" \
  --dry-run=client -o yaml | $KUBECTL apply -f - >/dev/null
$KUBECTL -n "$NAMESPACE" create secret generic "$SECRET_NAME" \
  --from-file=authorized_keys="$RUN_DIR/ssh/id_ed25519.pub" \
  --dry-run=client -o yaml | $KUBECTL apply -f - >/dev/null
# run-id-Label, damit teardown.sh ConfigMap/Secret eindeutig wieder findet
$KUBECTL -n "$NAMESPACE" label --overwrite configmap "$CM_NAME" "thesis.pybay.de/run-id=$RUN_ID_LABEL" >/dev/null
$KUBECTL -n "$NAMESPACE" label --overwrite secret "$SECRET_NAME" "thesis.pybay.de/run-id=$RUN_ID_LABEL" >/dev/null

export POD_NAME NAMESPACE IMAGE RUN_ID RUN_ID_LABEL SCENARIO REQ_ID REQ_ID_LABEL \
       VARIANT VARIANT_LABEL CELL_LABEL GT_HASH STATE_HASH CM_NAME SECRET_NAME
envsubst '${POD_NAME} ${NAMESPACE} ${IMAGE} ${RUN_ID} ${RUN_ID_LABEL} ${SCENARIO} ${REQ_ID} ${REQ_ID_LABEL} ${VARIANT} ${VARIANT_LABEL} ${CELL_LABEL} ${GT_HASH} ${STATE_HASH} ${CM_NAME} ${SECRET_NAME}' \
  < "$REPO_ROOT/kubernetes/target-pod.tmpl.yaml" > "$RUN_DIR/pod.yaml"
$KUBECTL apply -f "$RUN_DIR/pod.yaml" >/dev/null

info "warte auf Pod Ready (apt install openssh-server + setup.sh laufen im Pod) ..."
$KUBECTL -n "$NAMESPACE" wait --for=condition=Ready "pod/$POD_NAME" --timeout=300s \
  || die "Pod nicht Ready - '$KUBECTL -n $NAMESPACE describe pod $POD_NAME' pruefen"

# --- Manifest (pre-committed) ---
cat > "$RUN_DIR/manifest.json" <<JSON
{
  "run_id": "$RUN_ID",
  "scenario": "$SCENARIO",
  "requirement_id": "$REQ_ID",
  "module_id": "$MODULE_ID",
  "category": "$CATEGORY",
  "cell": "$CELL",
  "variant": "$VARIANT",
  "expected_verdict": "$EXPECTED_VERDICT",
  "expected_compliant": $EXPECTED_COMPLIANT,
  "ground_truth_sha256": "$GT_HASH",
  "state_sha256": "$STATE_HASH",
  "sudoers_sha256": "$SUDOERS_HASH",
  "image": "$IMAGE",
  "namespace": "$NAMESPACE",
  "pod_name": "$POD_NAME",
  "configmap_name": "$CM_NAME",
  "secret_name": "$SECRET_NAME",
  "run_id_label": "$RUN_ID_LABEL",
  "node_selector": "role=lab",
  "ssh": { "host": "127.0.0.1", "port": $PORT, "user": "audit", "private_key": "runs/$RUN_ID/ssh/id_ed25519" },
  "otel_resource_attributes": "$OTEL_ATTRS",
  "created_utc": "$TS",
  "phase": "up",
  "agent": { "verdict": null, "passed": null, "notes": null, "ended_utc": null }
}
JSON

# --- Port-Forward im Hintergrund ---
$KUBECTL -n "$NAMESPACE" port-forward "pod/$POD_NAME" "$PORT:22" >"$RUN_DIR/portforward.log" 2>&1 &
echo $! > "$RUN_DIR/portforward.pid"
sleep 2

# --- Preflight: SSH-Login MUSS funktionieren, sonst ist der Lauf nicht auswertbar ---
# Verhindert False Pass aus falschem Grund (Agent kommt nie auf den Host und
# urteilt zufaellig "nicht verifizierbar"). Bei Fehlschlag: harter Abbruch,
# kein Agentenlauf, Pod bleibt zur Diagnose stehen.
if ! ssh -i "$RUN_DIR/ssh/id_ed25519" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
       -o IdentitiesOnly=yes -o PreferredAuthentications=publickey -o BatchMode=yes \
       -o ConnectTimeout=10 -p "$PORT" audit@127.0.0.1 true 2>"$RUN_DIR/preflight.log"; then
  die "Preflight-SSH fehlgeschlagen (audit@127.0.0.1:$PORT) - Lauf NICHT auswertbar, kein Agent gestartet. Details: $RUN_DIR/preflight.log | abraeumen: scripts/teardown.sh $RUN_ID"
fi
info "Preflight-SSH ok (audit-Login funktioniert)."

# --- Schicht 2: Agent fahren + vollstaendigen Output pro Lauf sichern ---
if [[ "$RUN_AGENT" == true ]]; then
  if command -v claude >/dev/null 2>&1; then
    # DZ2-Isolation: Agent laeuft in einem leeren Arbeitsverzeichnis AUSSERHALB
    # des Repos; nur der private SSH-Key liegt dort. So kein Zugriff auf Ground
    # Truth, Szenario-Dateien oder variant.env (das erwartete Urteil).
    AGENT_CWD="$(mktemp -d "${TMPDIR:-/tmp}/lab-agent-XXXXXX")"
    cp "$RUN_DIR/ssh/id_ed25519" "$AGENT_CWD/id_ed25519"
    chmod 600 "$AGENT_CWD/id_ed25519"
    AGENT_PROMPT="$(cat "$SCEN_DIR/check-prompt.md")

SSH-Zugang (read-only): ssh -i id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $PORT audit@127.0.0.1"
    info "starte Agent (claude -p --output-format json) in isoliertem CWD ..."
    # --allowedTools "Bash": im headless-Modus (claude -p) gibt es keine
    # interaktive Freigabe; ohne Allowlist werden ssh/Bash-Calls still
    # verweigert. Das Ziel-Pod ist ephemer + read-only (sudoers-Whitelist),
    # daher ist Bash-Freigabe im Lab vertretbar.
    ( cd "$AGENT_CWD" && OTEL_RESOURCE_ATTRIBUTES="$OTEL_ATTRS" \
        claude -p "$AGENT_PROMPT" --output-format json --allowedTools "Bash" ) \
        > "$RUN_DIR/agent_output.json" 2> "$RUN_DIR/agent_stderr.log" || true
    # vollstaendiges Session-Transcript (Prompt+Antwort+Tool-I/O) mitnehmen
    SID="$(sed -n 's/.*"session_id":[[:space:]]*"\([^"]*\)".*/\1/p' "$RUN_DIR/agent_output.json" | head -n1)"
    if [[ -n "$SID" ]]; then
      TRANSCRIPT="$(find "$HOME/.claude/projects" -name "$SID.jsonl" 2>/dev/null | head -n1)"
      [[ -n "$TRANSCRIPT" ]] && cp "$TRANSCRIPT" "$RUN_DIR/transcript.jsonl"
    fi
    rm -f "$AGENT_CWD/id_ed25519"; rmdir "$AGENT_CWD" 2>/dev/null || true
    info "Agent fertig -> runs/$RUN_ID/agent_output.json (+ transcript.jsonl falls gefunden)"
    info "Urteil festhalten + abraeumen: scripts/teardown.sh $RUN_ID --verdict <konform|nicht_konform|nicht_verifizierbar>"
    echo "$RUN_ID"
    exit 0
  fi
  info "--agent gesetzt, aber 'claude' nicht im PATH -> manueller Modus."
fi

cat >&2 <<EOF

================ LAUF BEREIT ================
 Run-ID : $RUN_ID
 Zelle  : $CELL | erwartetes Urteil: $EXPECTED_VERDICT
 SSH    : ssh -i runs/$RUN_ID/ssh/id_ed25519 -o StrictHostKeyChecking=no -p $PORT audit@127.0.0.1

 Agent (Claude Code) mit run.id-Telemetrie starten:

   OTEL_RESOURCE_ATTRIBUTES="$OTEL_ATTRS" \\
   claude -p --allowedTools "Bash" "\$(cat "$SCEN_DIR/check-prompt.md")

   SSH-Zugang (read-only): ssh -i runs/$RUN_ID/ssh/id_ed25519 -o StrictHostKeyChecking=no -p $PORT audit@127.0.0.1"

 Danach abraeumen + Urteil festhalten:
   scripts/teardown.sh $RUN_ID --verdict <konform|nicht_konform|nicht_verifizierbar> --notes "..."
============================================
EOF
echo "$RUN_ID"
