#!/usr/bin/env bash
#
# Entrypoint des Pruefagenten (laeuft als non-root 'agent' im Job-Pod).
#
# Eingaben (read-only gemountet):
#   /etc/agent-key/id_ed25519     per-run SSH-Key (Secret, defaultMode 0444)
#   /etc/agent-prompt/check-prompt.md  Pruef-Prompt (ConfigMap, OHNE Ground Truth)
#
# Ausgabe: strukturiert auf stdout, von run.sh ueber Marker zerlegt
# (agent_output.json / agent_stderr.log / transcript.jsonl). kubectl-Logs
# bleiben auch nach Pod-Ende lesbar -> kein exec/cp auf einen beendeten Pod.
set -uo pipefail

# SSH-Key in den Home-Bereich kopieren und auf 600 setzen (ssh besteht auf
# restriktiven Rechten; die Secret-Mount-Datei ist 0444 und root-owned).
install -d -m 700 "$HOME/.ssh"
install -m 600 /etc/agent-key/id_ed25519 "$HOME/.ssh/id_ed25519"

PROMPT="$(cat /etc/agent-prompt/check-prompt.md)"

set +e
# Summativer Lauf (DZ5/DZ9):
#  - Modell-Pin via ANTHROPIC_MODEL (Env, Job-Template),
#  - Hintergrund-/Small-Fast-Modell via ANTHROPIC_DEFAULT_HAIKU_MODEL (= Pin ->
#    keine Haiku-Calls, modelUsage enthaelt nur den Pin),
#  - Reasoning-Effort via --effort (Hauptlauf-Setzung: high),
#  - Permissions: --dangerously-skip-permissions (headless/unbeaufsichtigt; das
#    Target ist read-only durch die sudoers-Whitelist, daher vertretbar).
# HINWEIS: exakte Flag-Namen (--effort / --dangerously-skip-permissions) vor dem
# Image-Rebuild mit 'claude --help' der gepinnten CLI-Version gegenpruefen.
claude -p "$PROMPT" \
  --output-format json \
  --effort "${AGENT_EFFORT:-high}" \
  --dangerously-skip-permissions \
  >/tmp/out.json 2>/tmp/err.log
rc=$?
set -e

echo "===AGENT_OUTPUT_JSON==="
cat /tmp/out.json
printf '\n===AGENT_STDERR===\n'
cat /tmp/err.log
SID="$(jq -r '.session_id // empty' /tmp/out.json 2>/dev/null || true)"
printf '\n===TRANSCRIPT_JSONL===\n'
[ -n "$SID" ] && find "$HOME/.claude" -name "$SID.jsonl" -exec cat {} \; 2>/dev/null
printf '\n===END===\n'

exit "$rc"
