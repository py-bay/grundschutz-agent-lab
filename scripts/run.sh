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
AGENT_INCLUSTER=false
TARGET=k8s          # k8s (Hauptlauf, Pod) | docker (lokaler Container, DZ9-Souveraenitaetslauf)
BACKEND=claude      # claude (Hauptlauf) | opencode (lokaler offener Agent, DZ9)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2;;
    --agent) RUN_AGENT=true; shift;;                       # claude lokal auf dem Operator (Dev/Fallback)
    --agent-incluster) AGENT_INCLUSTER=true; RUN_AGENT=true; shift;;  # claude als k8s-Job (laptop-frei, Standard fuer den Hauptlauf)
    --target) TARGET="$2"; shift 2;;                       # Ziel-Substrat: k8s|docker
    --backend) BACKEND="$2"; RUN_AGENT=true; shift 2;;     # Pruefagent: claude|opencode (impliziert lokalen Agentenlauf)
    *) die "unbekanntes Argument: $1";;
  esac
done
case "$TARGET" in k8s|docker) :;; *) die "--target muss k8s|docker sein (war: $TARGET)";; esac
case "$BACKEND" in claude|opencode) :;; *) die "--backend muss claude|opencode sein (war: $BACKEND)";; esac
# opencode-Backend laeuft nur lokal (kein in-cluster-Job-Image); docker-Target nur lokal.
[[ "$BACKEND" == opencode && "$AGENT_INCLUSTER" == true ]] && die "--backend opencode ist mit --agent-incluster nicht kombinierbar (opencode laeuft lokal)."
[[ "$TARGET" == docker && "$AGENT_INCLUSTER" == true ]] && die "--target docker ist mit --agent-incluster nicht kombinierbar (kein Cluster)."

need openssl; need ssh-keygen
if [[ "$TARGET" == k8s ]]; then
  need envsubst
  info "kubectl: $KUBECTL"
else
  need docker
  info "Target-Substrat: docker (lokaler Container, kein Cluster)"
fi

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
ERGEBNISKLASSE="$(yval ergebnisklasse)"
[[ -n "$REQ_ID" ]] || REQ_ID="$SCENARIO"
[[ -n "$CATEGORY" ]] || CATEGORY="A"
[[ -n "$ERGEBNISKLASSE" ]] || ERGEBNISKLASSE="-"

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
  rm -f "$STAGE/sudoers"            # Variant-Whitelist laeuft separat als audit_sudoers, nicht roh in /etc/thesis
  EXPECTED_VERDICT="$(sed -n 's/^EXPECTED_VERDICT=//p' "$VAR_DIR/variant.env" 2>/dev/null | tr -d '"' | head -n1)"
  # Optional: Variante darf die szenario-weite Ergebnisklasse ueberschreiben
  # (Sachurteil-Paare, z.B. SYS.2.1.A18: compliant=1_sauber_konform,
  # non_compliant=2_sauber_nicht_konform). Ohne Eintrag bleibt die scenario.yaml.
  EK_OVERRIDE="$(sed -n 's/^EXPECTED_ERGEBNISKLASSE=//p' "$VAR_DIR/variant.env" 2>/dev/null | tr -d '"' | head -n1)"
  [[ -n "$EK_OVERRIDE" ]] && ERGEBNISKLASSE="$EK_OVERRIDE"
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

# sudoers (read-only Kommando-Whitelist): variant-spezifisch (variants/<v>/sudoers)
# vor szenario-weit (<scen>/sudoers) vor Legacy-Default. So kann eine Variante dem
# Auditor gezielt mehr/weniger Lesezugriff geben - der saubere Ergebnisklasse-4-Kontrast:
# 'locked' ohne Policy-Leserecht (-> nicht_verifizierbar), 'readable' mit (-> konform),
# bei in beiden Faellen identischer, korrekt 0440-gerechteter Policy.
if [[ -f "$VAR_DIR/sudoers" ]]; then
  cp "$VAR_DIR/sudoers" "$STAGE/audit_sudoers"
elif [[ -f "$SCEN_DIR/sudoers" ]]; then
  cp "$SCEN_DIR/sudoers" "$STAGE/audit_sudoers"
else
  printf 'audit ALL=(root) NOPASSWD: /usr/sbin/sshd -T\n' > "$STAGE/audit_sudoers"
fi

# --- Run-Identitaet + Provenance (Hashes stehen VOR dem Agentenlauf fest) ---
GT_HASH="$(sha256 "$GT_SRC")"
SUDOERS_HASH="$(sha256 "$STAGE/audit_sudoers")"
# Zustands-Hash ueber alle gemounteten Szenario-Dateien, reihenfolgestabil
STATE_HASH="$(find "$STAGE" -type f -exec sha256sum {} + | awk '{print $1}' | sort | sha256sum | awk '{print $1}')"
# Pruef-Prompt-Hash (DP7, Kontext-Huelle): hasht die pre-committed check-prompt.md
# des Szenarios - ohne die zur Laufzeit angehaengte, dynamische SSH-Zugangszeile.
PROMPT_SRC="$SCEN_DIR/check-prompt.md"
PROMPT_HASH="$( [[ -f "$PROMPT_SRC" ]] && sha256 "$PROMPT_SRC" || echo "-" )"

# Ephemeres Schluesselpaar fuer genau diesen Lauf (privater Key bleibt lokal)
ssh-keygen -t ed25519 -N "" -C "audit@$RUN_ID" -f "$RUN_DIR/ssh/id_ed25519" >/dev/null

POD_NAME="target-$(sanitize "${VARIANT}-${RAND}")"
CM_NAME="scenario-$(sanitize "${VARIANT}-${RAND}")"
SECRET_NAME="authkeys-$(sanitize "${VARIANT}-${RAND}")"
CONTAINER="lab-target-$(sanitize "${VARIANT}-${RAND}")"   # docker-Target dieses Laufs
RUN_ID_LABEL="$(label_safe "$RUN_ID")"
REQ_ID_LABEL="$(label_safe "$REQ_ID")"
VARIANT_LABEL="$(label_safe "$VARIANT")"
ERGEBNISKLASSE_LABEL="$(label_safe "$ERGEBNISKLASSE")"

# OTEL-Resource-Attribute (keine Leerzeichen erlaubt) -> taggt jede
# Claude-Code-Metrik/jedes Event mit run.id, in OpenObserve pro Lauf abfragbar
OTEL_ATTRS="run.id=${RUN_ID},scenario=${SCENARIO},variant=${VARIANT},requirement.id=${REQ_ID},ergebnisklasse=${ERGEBNISKLASSE}"

info "Run-ID: $RUN_ID"
info "Kategorie/Ergebnisklasse: $CATEGORY / $ERGEBNISKLASSE | erwartetes Urteil: $EXPECTED_VERDICT"

if [[ "$TARGET" == k8s ]]; then
  info "Namespace/Pod: $NAMESPACE/$POD_NAME (node ${LAB_NODE_SELECTOR:-unpinned})"
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
         VARIANT VARIANT_LABEL ERGEBNISKLASSE_LABEL GT_HASH STATE_HASH CM_NAME SECRET_NAME \
         LAB_NODE_KEY LAB_NODE_VALUE LAB_TOL_KEY LAB_TOL_VALUE
  envsubst '${POD_NAME} ${NAMESPACE} ${IMAGE} ${RUN_ID} ${RUN_ID_LABEL} ${SCENARIO} ${REQ_ID} ${REQ_ID_LABEL} ${VARIANT} ${VARIANT_LABEL} ${ERGEBNISKLASSE_LABEL} ${GT_HASH} ${STATE_HASH} ${CM_NAME} ${SECRET_NAME} ${LAB_NODE_KEY} ${LAB_NODE_VALUE} ${LAB_TOL_KEY} ${LAB_TOL_VALUE}' \
    < "$REPO_ROOT/kubernetes/target-pod.tmpl.yaml" > "$RUN_DIR/pod.yaml"
  # Substrat-Bloecke abschalten, wenn per "" deaktiviert (siehe lib.sh).
  [[ -n "$LAB_NODE_SELECTOR" ]] || strip_block node-selector "$RUN_DIR/pod.yaml"
  [[ -n "$LAB_TOLERATION"    ]] || strip_block toleration    "$RUN_DIR/pod.yaml"
  $KUBECTL apply -f "$RUN_DIR/pod.yaml" >/dev/null

  info "warte auf Pod Ready (apt install openssh-server + setup.sh laufen im Pod) ..."
  $KUBECTL -n "$NAMESPACE" wait --for=condition=Ready "pod/$POD_NAME" --timeout=300s \
    || die "Pod nicht Ready - '$KUBECTL -n $NAMESPACE describe pod $POD_NAME' pruefen"
else
  # --- Lokales Docker-Target (DZ9-Souveraenitaetslauf, Cluster nicht erreichbar) ---
  # Inhaltlich identischer Bootstrap zum Pod (scripts/target-bootstrap.sh).
  info "Target-Container: $CONTAINER (image $IMAGE), Port 127.0.0.1:$PORT -> 22"
  mkdir -p "$RUN_DIR/authkeys"
  cp "$RUN_DIR/ssh/id_ed25519.pub" "$RUN_DIR/authkeys/authorized_keys"  # nur der Pubkey kommt ins Target
  "$REPO_ROOT/scripts/target-docker.sh" up \
    "$STAGE" "$RUN_DIR/authkeys/authorized_keys" "$PORT" "$CONTAINER" "$IMAGE" \
    "$VARIANT" "$ERGEBNISKLASSE_LABEL" "$RUN_ID" \
    || die "Docker-Target nicht hochgekommen - 'docker logs $CONTAINER' pruefen | abraeumen: scripts/teardown.sh $RUN_ID"
fi

# --- Manifest (pre-committed) ---
cat > "$RUN_DIR/manifest.json" <<JSON
{
  "run_id": "$RUN_ID",
  "scenario": "$SCENARIO",
  "requirement_id": "$REQ_ID",
  "module_id": "$MODULE_ID",
  "category": "$CATEGORY",
  "ergebnisklasse": "$ERGEBNISKLASSE",
  "variant": "$VARIANT",
  "expected_verdict": "$EXPECTED_VERDICT",
  "expected_compliant": $EXPECTED_COMPLIANT,
  "ground_truth_sha256": "$GT_HASH",
  "prompt_sha256": "$PROMPT_HASH",
  "state_sha256": "$STATE_HASH",
  "sudoers_sha256": "$SUDOERS_HASH",
  "image": "$IMAGE",
  "target": "$TARGET",
  "backend": "$BACKEND",
  "container_name": "$CONTAINER",
  "namespace": "$NAMESPACE",
  "pod_name": "$POD_NAME",
  "configmap_name": "$CM_NAME",
  "secret_name": "$SECRET_NAME",
  "run_id_label": "$RUN_ID_LABEL",
  "node_selector": "$LAB_NODE_SELECTOR",
  "ssh": { "host": "127.0.0.1", "port": $PORT, "user": "audit", "private_key": "runs/$RUN_ID/ssh/id_ed25519" },
  "otel_resource_attributes": "$OTEL_ATTRS",
  "created_utc": "$TS",
  "phase": "up",
  "agent": { "verdict": null, "passed": null, "notes": null, "ended_utc": null }
}
JSON

# --- Port-Forward im Hintergrund (nur k8s; das docker-Target publisht :22 direkt) ---
if [[ "$TARGET" == k8s ]]; then
  $KUBECTL -n "$NAMESPACE" port-forward "pod/$POD_NAME" "$PORT:22" >"$RUN_DIR/portforward.log" 2>&1 &
  echo $! > "$RUN_DIR/portforward.pid"
  sleep 2
fi

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

# --- Schicht 2a: Agent als k8s-Job IN-CLUSTER (laptop-frei) ---
# DZ2 per Konstruktion ueber Dateisystem-Isolation: der Agent-Pod bekommt nur
# Pruef-Prompt (ConfigMap, ohne GT) + privaten Key (Secret), keinen Repo-/Host-
# Mount, kein ServiceAccount-Token. Die Ground Truth liegt nur hier operator-
# seitig und gelangt nie in den Cluster. Der Preflight oben bleibt der einzige
# operator-seitige SSH-Schritt; den Port-Forward braucht der In-Cluster-Agent
# nicht (er erreicht das Target ueber einen headless Service).
if [[ "$AGENT_INCLUSTER" == true ]]; then
  if [[ -f "$RUN_DIR/portforward.pid" ]]; then
    kill "$(cat "$RUN_DIR/portforward.pid")" 2>/dev/null || true
    rm -f "$RUN_DIR/portforward.pid"
  fi
  $KUBECTL -n "$NAMESPACE" get secret claude-oauth >/dev/null 2>&1 \
    || die "Secret 'claude-oauth' fehlt im Namespace $NAMESPACE - einmalig anlegen (siehe README/runbook)."
  # otel-auth nur noetig, wenn Telemetrie-Export aktiv ist (OTEL_ENDPOINT nicht leer).
  if [[ -n "$OTEL_ENDPOINT" ]]; then
    $KUBECTL -n "$NAMESPACE" get secret otel-auth >/dev/null 2>&1 \
      || die "Secret 'otel-auth' fehlt im Namespace $NAMESPACE - einmalig anlegen (siehe README/runbook) oder Telemetrie mit OTEL_ENDPOINT=\"\" abschalten."
  fi

  TARGET_SVC="target-svc-$(sanitize "${VARIANT}-${RAND}")"
  JOB_NAME="agent-$(sanitize "${VARIANT}-${RAND}")"
  AGENT_KEY_SECRET="agentkey-$(sanitize "${VARIANT}-${RAND}")"
  AGENT_PROMPT_CM="agentprompt-$(sanitize "${VARIANT}-${RAND}")"

  # Headless Service -> stabiler DNS-Name auf das Target-Pod dieses Laufs.
  export TARGET_SVC NAMESPACE RUN_ID_LABEL
  envsubst '${TARGET_SVC} ${NAMESPACE} ${RUN_ID_LABEL}' \
    < "$REPO_ROOT/kubernetes/target-service.tmpl.yaml" > "$RUN_DIR/target-service.yaml"
  $KUBECTL apply -f "$RUN_DIR/target-service.yaml" >/dev/null

  # per-run Key-Secret (privater Key fuer den Agenten).
  $KUBECTL -n "$NAMESPACE" create secret generic "$AGENT_KEY_SECRET" \
    --from-file=id_ed25519="$RUN_DIR/ssh/id_ed25519" \
    --dry-run=client -o yaml | $KUBECTL apply -f - >/dev/null

  # Pruef-Prompt: check-prompt.md (OHNE GT) + Zugangszeile auf den Service.
  # Schluesselpfad absolut (Entrypoint kopiert nach /home/agent/.ssh).
  PROMPT_FILE="$RUN_DIR/agent-prompt.md"
  {
    cat "$SCEN_DIR/check-prompt.md"
    printf '\nSSH-Zugang (read-only): ssh -i /home/agent/.ssh/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 22 audit@%s.%s.svc.cluster.local\n' \
      "$TARGET_SVC" "$NAMESPACE"
  } > "$PROMPT_FILE"
  $KUBECTL -n "$NAMESPACE" create configmap "$AGENT_PROMPT_CM" \
    --from-file=check-prompt.md="$PROMPT_FILE" \
    --dry-run=client -o yaml | $KUBECTL apply -f - >/dev/null

  # Label fuer label-basiertes teardown.
  $KUBECTL -n "$NAMESPACE" label --overwrite secret "$AGENT_KEY_SECRET" "thesis.pybay.de/run-id=$RUN_ID_LABEL" >/dev/null
  $KUBECTL -n "$NAMESPACE" label --overwrite configmap "$AGENT_PROMPT_CM" "thesis.pybay.de/run-id=$RUN_ID_LABEL" >/dev/null
  $KUBECTL -n "$NAMESPACE" label --overwrite service "$TARGET_SVC" "thesis.pybay.de/run-id=$RUN_ID_LABEL" >/dev/null

  # Agent-Job rendern + starten.
  export JOB_NAME AGENT_IMAGE AGENT_MODEL AGENT_EFFORT AGENT_KEY_SECRET AGENT_PROMPT_CM OTEL_ATTRS REQ_ID_LABEL ERGEBNISKLASSE_LABEL \
         AGENT_PULL_SECRET OTEL_ENDPOINT LAB_NODE_KEY LAB_NODE_VALUE LAB_TOL_KEY LAB_TOL_VALUE
  envsubst '${JOB_NAME} ${NAMESPACE} ${RUN_ID_LABEL} ${REQ_ID_LABEL} ${ERGEBNISKLASSE_LABEL} ${AGENT_IMAGE} ${AGENT_MODEL} ${AGENT_EFFORT} ${AGENT_KEY_SECRET} ${AGENT_PROMPT_CM} ${OTEL_ATTRS} ${AGENT_PULL_SECRET} ${OTEL_ENDPOINT} ${LAB_NODE_KEY} ${LAB_NODE_VALUE} ${LAB_TOL_KEY} ${LAB_TOL_VALUE}' \
    < "$REPO_ROOT/kubernetes/agent-job.tmpl.yaml" > "$RUN_DIR/agent-job.yaml"
  # Substrat-Bloecke abschalten, wenn per "" deaktiviert (siehe lib.sh).
  [[ -n "$AGENT_PULL_SECRET"  ]] || strip_block pull-secret   "$RUN_DIR/agent-job.yaml"
  [[ -n "$OTEL_ENDPOINT"      ]] || strip_block otel          "$RUN_DIR/agent-job.yaml"
  [[ -n "$LAB_NODE_SELECTOR"  ]] || strip_block node-selector "$RUN_DIR/agent-job.yaml"
  [[ -n "$LAB_TOLERATION"     ]] || strip_block toleration    "$RUN_DIR/agent-job.yaml"
  # Modell-Pin optional: ohne AGENT_MODEL die ANTHROPIC_MODEL- UND
  # ANTHROPIC_DEFAULT_HAIKU_MODEL-Env-Zeilen entfernen (sonst liefe der Agent mit
  # leerem Modellnamen). Mit AGENT_MODEL bleiben beide Pins. AGENT_EFFORT hat in
  # lib.sh einen Default (high) und bleibt immer stehen.
  [[ -n "$AGENT_MODEL" ]] || sed -i -e '/name: ANTHROPIC_MODEL/,+1d' \
    -e '/name: ANTHROPIC_DEFAULT_HAIKU_MODEL/,+1d' "$RUN_DIR/agent-job.yaml"
  $KUBECTL apply -f "$RUN_DIR/agent-job.yaml" >/dev/null
  info "Agent-Job $JOB_NAME gestartet (Image $AGENT_IMAGE), warte auf Completion ..."

  # Auf Abschluss warten (complete ODER failed), Logs unabhaengig vom Status holen.
  $KUBECTL -n "$NAMESPACE" wait --for=condition=complete "job/$JOB_NAME" --timeout=600s 2>/dev/null \
    || $KUBECTL -n "$NAMESPACE" wait --for=condition=failed "job/$JOB_NAME" --timeout=10s 2>/dev/null || true

  $KUBECTL -n "$NAMESPACE" logs "job/$JOB_NAME" --tail=-1 > "$RUN_DIR/agent_job.log" 2>/dev/null || true
  # Marker-getrennte stdout in die Lauf-Artefakte zerlegen.
  awk -v out="$RUN_DIR/agent_output.json" -v err="$RUN_DIR/agent_stderr.log" -v tr="$RUN_DIR/transcript.jsonl" '
    /^===AGENT_OUTPUT_JSON===$/{f="o";next} /^===AGENT_STDERR===$/{f="e";next}
    /^===TRANSCRIPT_JSONL===$/{f="t";next} /^===END===$/{f="";next}
    f=="o"{print > out} f=="e"{print > err} f=="t"{print > tr}' "$RUN_DIR/agent_job.log" 2>/dev/null || true

  if [[ -s "$RUN_DIR/agent_output.json" ]]; then
    info "Agent fertig -> runs/$RUN_ID/agent_output.json (+ transcript.jsonl, agent_job.log)"
  else
    info "WARNUNG: kein agent_output.json aus den Job-Logs extrahiert - runs/$RUN_ID/agent_job.log pruefen."
  fi
  info "Urteil festhalten + abraeumen: scripts/teardown.sh $RUN_ID --verdict <konform|nicht_konform|nicht_verifizierbar>"
  echo "$RUN_ID"
  exit 0
fi

# --- Schicht 2b: Agent lokal auf dem Operator (Dev/Fallback, --agent / --backend) ---
if [[ "$RUN_AGENT" == true ]]; then
  # DZ2-Isolation (backend-unabhaengig): Agent laeuft in einem leeren
  # Arbeitsverzeichnis AUSSERHALB des Repos; nur der private SSH-Key liegt dort.
  # Kein Zugriff auf Ground Truth, Szenario-Dateien oder variant.env (Soll-Urteil).
  AGENT_CWD="$(mktemp -d "${TMPDIR:-/tmp}/lab-agent-XXXXXX")"
  cp "$RUN_DIR/ssh/id_ed25519" "$AGENT_CWD/id_ed25519"
  chmod 600 "$AGENT_CWD/id_ed25519"
  AGENT_PROMPT="$(cat "$SCEN_DIR/check-prompt.md")

SSH-Zugang (read-only): ssh -i id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $PORT audit@127.0.0.1"

  if [[ "$BACKEND" == claude ]]; then
    if command -v claude >/dev/null 2>&1; then
      info "starte Agent (claude -p --output-format json) in isoliertem CWD ..."
      # --allowedTools "Bash": im headless-Modus (claude -p) gibt es keine
      # interaktive Freigabe; ohne Allowlist werden ssh/Bash-Calls still
      # verweigert. Das Ziel ist ephemer + read-only (sudoers-Whitelist),
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
    rm -f "$AGENT_CWD/id_ed25519"; rmdir "$AGENT_CWD" 2>/dev/null || true
    info "--agent gesetzt, aber 'claude' nicht im PATH -> manueller Modus."
  else
    # --- Backend opencode (lokal, souveraen, offen; DZ9-Kern) ---------------------
    # Einziger Unterschied zum claude-Pfad: das Werkzeug + die Normalisierung des
    # Event-Streams in DASSELBE agent_output.json-Schema. Downstream (extract_verdict,
    # teardown.sh, aggregate.py) bleibt unveraendert. Kein OTel (opencode #14697) ->
    # Telemetrie kommt aus dem normalisierten Artefakt (Kosten=0, lokal). Permission
    # ohne 'ask' (#14473-Hang) via --dangerously-skip-permissions; read-only liegt
    # ohnehin server-seitig in der Target-sudoers-Whitelist (DZ6).
    command -v opencode >/dev/null 2>&1 || die "--backend opencode: 'opencode' nicht im PATH (npm i -g opencode-ai@<version>)."
    command -v python3  >/dev/null 2>&1 || die "--backend opencode: python3 fuer die Normalisierung noetig."
    OPENCODE_MODEL="${OPENCODE_MODEL:-ollama/gemma4:26b-32k}"
    OPENCODE_VARIANT="${OPENCODE_VARIANT:-}"     # optional: provider-Reasoning-Effort (high|max|...)
    OPENCODE_DIGEST="${OPENCODE_DIGEST:-}"       # optional: Ollama-Modell-Digest (Reproduzierbarkeit)
    # Defensiver Timeout (lokale Inferenz auf iGPU ist langsam; ein haengender
    # opencode-Lauf - z.B. durch eine stale opencode-Server-Instanz - soll nicht
    # ewig laufen). Override per OPENCODE_TIMEOUT (Sekunden), 0 = kein Timeout.
    OPENCODE_TIMEOUT="${OPENCODE_TIMEOUT:-1800}"
    OC_TIMEOUT_CMD=(); [[ "$OPENCODE_TIMEOUT" != 0 ]] && OC_TIMEOUT_CMD=(timeout "$OPENCODE_TIMEOUT")
    info "starte Agent (opencode run --format json, model=$OPENCODE_MODEL${OPENCODE_VARIANT:+, variant=$OPENCODE_VARIANT}, timeout=${OPENCODE_TIMEOUT}s) in isoliertem CWD ..."
    START_MS=$(date +%s%3N)
    set +e
    ( cd "$AGENT_CWD" && "${OC_TIMEOUT_CMD[@]}" opencode run "$AGENT_PROMPT" --format json \
        -m "$OPENCODE_MODEL" ${OPENCODE_VARIANT:+--variant "$OPENCODE_VARIANT"} \
        --dangerously-skip-permissions ) \
        > "$RUN_DIR/opencode_events.jsonl" 2> "$RUN_DIR/agent_stderr.log"
    OC_RC=$?
    set -e
    END_MS=$(date +%s%3N)
    python3 "$REPO_ROOT/scripts/normalize_opencode.py" \
        --events "$RUN_DIR/opencode_events.jsonl" --wall-ms "$((END_MS-START_MS))" \
        --rc "$OC_RC" --model "$OPENCODE_MODEL" --model-digest "$OPENCODE_DIGEST" \
        > "$RUN_DIR/agent_output.json" 2>>"$RUN_DIR/agent_stderr.log" || true
    # Roh-Eventstream IST das Transcript (Provenienz/Audit, DZ3).
    cp "$RUN_DIR/opencode_events.jsonl" "$RUN_DIR/transcript.jsonl" 2>/dev/null || true
    rm -f "$AGENT_CWD/id_ed25519"; rmdir "$AGENT_CWD" 2>/dev/null || true
    info "Agent fertig -> runs/$RUN_ID/agent_output.json (+ transcript.jsonl), opencode rc=$OC_RC"
    info "Urteil festhalten + abraeumen: scripts/teardown.sh $RUN_ID --verdict <konform|nicht_konform|nicht_verifizierbar>"
    echo "$RUN_ID"
    exit 0
  fi
fi

cat >&2 <<EOF

================ LAUF BEREIT ================
 Run-ID : $RUN_ID
 Ergebnisklasse  : $ERGEBNISKLASSE | erwartetes Urteil: $EXPECTED_VERDICT
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
