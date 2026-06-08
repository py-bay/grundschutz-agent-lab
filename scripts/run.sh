#!/usr/bin/env bash
#
# run.sh - zieht EIN ephemeres SSH-Zielsystem fuer einen Lab-Lauf hoch,
# schreibt ein pre-committed Run-Manifest und oeffnet einen Port-Forward.
# Der Pod laeuft NICHT dauerhaft: teardown.sh raeumt ihn wieder ab.
#
# Aufruf:
#   scripts/run.sh <scenario-id> <compliant|non_compliant> [--port 2222]
#
# Voraussetzungen auf dem Betreiber-Laptop:
#   - kubectl mit gueltiger kubeconfig (ggf. via SSH-Tunnel zum API-Server)
#   - envsubst (gettext), openssl, ssh-keygen
#
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -ge 2 ]] || die "Aufruf: run.sh <scenario-id> <compliant|non_compliant> [--port N]"
SCENARIO="$1"; VARIANT="$2"; shift 2
PORT=2222
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2;;
    *) die "unbekanntes Argument: $1";;
  esac
done
[[ "$VARIANT" == "compliant" || "$VARIANT" == "non_compliant" ]] || die "Variante muss compliant|non_compliant sein"

need kubectl; need envsubst; need openssl; need ssh-keygen

# Szenario aufloesen (unter scenarios/*/<id>/)
SCEN_DIR="$(find "$REPO_ROOT/scenarios" -maxdepth 2 -type d -name "$SCENARIO" | head -n1)"
[[ -n "$SCEN_DIR" ]] || die "Szenario nicht gefunden: $SCENARIO"
SSHD_SRC="$SCEN_DIR/variants/$VARIANT/sshd_config"
GT_SRC="$SCEN_DIR/ground_truth.md"
[[ -f "$SSHD_SRC" ]] || die "Variantendatei fehlt: $SSHD_SRC"
[[ -f "$GT_SRC" ]] || die "ground_truth.md fehlt: $GT_SRC"

REQ_ID="$(sed -n 's/^requirement_id:[[:space:]]*//p' "$SCEN_DIR/scenario.yaml" | head -n1)"
MODULE_ID="$(sed -n 's/^module:[[:space:]]*//p' "$SCEN_DIR/scenario.yaml" | head -n1)"
[[ -n "$REQ_ID" ]] || REQ_ID="$SCENARIO"
case "$VARIANT" in
  compliant) EXPECTED_COMPLIANT=true;;
  non_compliant) EXPECTED_COMPLIANT=false;;
esac

# --- Run-Identitaet + Provenance ---
TS="$(date -u +%Y%m%dT%H%M%SZ)"
RAND="$(openssl rand -hex 3)"
RUN_ID="${REQ_ID}__${VARIANT}__${TS}__${RAND}"
GT_HASH="$(sha256 "$GT_SRC")"
CONFIG_HASH="$(sha256 "$SSHD_SRC")"

RUN_DIR="$REPO_ROOT/runs/$RUN_ID"
mkdir -p "$RUN_DIR/ssh"

# Ephemeres Schluesselpaar fuer genau diesen Lauf (privater Key bleibt lokal)
ssh-keygen -t ed25519 -N "" -C "audit@$RUN_ID" -f "$RUN_DIR/ssh/id_ed25519" >/dev/null

POD_NAME="target-$(sanitize "${VARIANT}-${RAND}")"
CM_NAME="sshd-config-$(sanitize "${VARIANT}-${RAND}")"
SECRET_NAME="authkeys-$(sanitize "${VARIANT}-${RAND}")"
RUN_ID_LABEL="$(label_safe "$RUN_ID")"
REQ_ID_LABEL="$(label_safe "$REQ_ID")"

# OTEL-Resource-Attribute (keine Leerzeichen erlaubt) -> taggt jede
# Claude-Code-Metrik/jedes Event mit run.id, in OpenObserve pro Lauf abfragbar
OTEL_ATTRS="run.id=${RUN_ID},scenario=${SCENARIO},variant=${VARIANT},requirement.id=${REQ_ID}"

info "Run-ID: $RUN_ID"
info "Namespace/Pod: $NAMESPACE/$POD_NAME (node role=lab)"

# --- Cluster-Objekte erzeugen ---
kubectl apply -f "$REPO_ROOT/kubernetes/namespace.yaml" >/dev/null
kubectl -n "$NAMESPACE" create configmap "$CM_NAME" --from-file=sshd_config="$SSHD_SRC" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$NAMESPACE" create secret generic "$SECRET_NAME" \
  --from-file=authorized_keys="$RUN_DIR/ssh/id_ed25519.pub" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
# run-id-Label, damit teardown.sh ConfigMap/Secret eindeutig wieder findet
kubectl -n "$NAMESPACE" label --overwrite configmap "$CM_NAME" "thesis.pybay.de/run-id=$RUN_ID_LABEL" >/dev/null
kubectl -n "$NAMESPACE" label --overwrite secret "$SECRET_NAME" "thesis.pybay.de/run-id=$RUN_ID_LABEL" >/dev/null

export POD_NAME NAMESPACE IMAGE RUN_ID RUN_ID_LABEL SCENARIO REQ_ID REQ_ID_LABEL \
       VARIANT GT_HASH CONFIG_HASH CM_NAME SECRET_NAME
envsubst '${POD_NAME} ${NAMESPACE} ${IMAGE} ${RUN_ID} ${RUN_ID_LABEL} ${SCENARIO} ${REQ_ID} ${REQ_ID_LABEL} ${VARIANT} ${GT_HASH} ${CONFIG_HASH} ${CM_NAME} ${SECRET_NAME}' \
  < "$REPO_ROOT/kubernetes/target-pod.tmpl.yaml" > "$RUN_DIR/pod.yaml"
kubectl apply -f "$RUN_DIR/pod.yaml" >/dev/null

info "warte auf Pod Ready (apt install openssh-server laeuft im Pod) ..."
kubectl -n "$NAMESPACE" wait --for=condition=Ready "pod/$POD_NAME" --timeout=300s \
  || die "Pod nicht Ready - 'kubectl -n $NAMESPACE describe pod $POD_NAME' pruefen"

# --- Manifest (pre-committed: Hashes stehen VOR dem Agentenlauf fest) ---
cat > "$RUN_DIR/manifest.json" <<JSON
{
  "run_id": "$RUN_ID",
  "scenario": "$SCENARIO",
  "requirement_id": "$REQ_ID",
  "module_id": "$MODULE_ID",
  "category": "A",
  "variant": "$VARIANT",
  "expected_compliant": $EXPECTED_COMPLIANT,
  "ground_truth_sha256": "$GT_HASH",
  "config_sha256": "$CONFIG_HASH",
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
kubectl -n "$NAMESPACE" port-forward "pod/$POD_NAME" "$PORT:22" >"$RUN_DIR/portforward.log" 2>&1 &
echo $! > "$RUN_DIR/portforward.pid"
sleep 2

cat >&2 <<EOF

================ LAUF BEREIT ================
 Run-ID : $RUN_ID
 SSH    : ssh -i runs/$RUN_ID/ssh/id_ed25519 -o StrictHostKeyChecking=no -p $PORT audit@127.0.0.1

 Agent (Claude Code) mit run.id-Telemetrie starten:

   OTEL_RESOURCE_ATTRIBUTES="$OTEL_ATTRS" \\
   claude -p "\$(cat "$SCEN_DIR/check-prompt.md")

   SSH-Zugang (read-only): ssh -i runs/$RUN_ID/ssh/id_ed25519 -o StrictHostKeyChecking=no -p $PORT audit@127.0.0.1"

 Danach abraeumen + Urteil festhalten:
   scripts/teardown.sh $RUN_ID --verdict <konform|nicht_konform> --notes "..."
============================================
EOF
echo "$RUN_ID"
