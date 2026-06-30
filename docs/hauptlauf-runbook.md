# Hauptlauf-Runbook (summativer k=4-Lauf)

Schritt-fuer-Schritt fuer den summativen Hauptlauf und seine Auswertung. Das
Traeger-Set ist agent-validiert: fuenf saubere Traeger ueber den Ergebnisraum
EK1–5, je mit Adversarial-Varianten-Paar.

## Traeger-Set (gewertet)

| Item-ID | Ergebnisklasse(n) | Varianten |
|---------|-------------------|-----------|
| `SYS.2.1.A18-ssh-crypto-strength` | 1 + 2 | compliant / non_compliant |
| `SYS.1.1.A33-trust-store-baseline` | 3 | compliant / non_compliant |
| `SYS.1.1.A2-authpolicy-synthesis` | 3 | compliant / non_compliant |
| `SYS.1.1.A2-shadow-hash-rootonly` | 4 | locked / readable |
| `SYS.1.1.A39-central-mgmt-offhost` | 5 | central_offhost / unmanaged_local |

= 5 Items × 2 Varianten × k=4 = **40 gewertete Laeufe**. Die Befund-Traeger
`SYS.2.3.A1` (EK4) und `SYS.1.1.A19` (EK5) laufen **nicht** mit — sie werden nur in
der Diskussion gefuehrt (→ [`test-case-katalog.md`](test-case-katalog.md)).

## Vor dem Lauf (Pflicht)

1. **Modell + Effort + Permissions.** Der Lauf ist auf Modell und Reasoning-Effort
   gepinnt:
   ```bash
   export AGENT_MODEL=claude-opus-4-8      # Haupt- UND Hintergrundmodell
   export AGENT_EFFORT=high                # claude -p --effort high (lib.sh-Default)
   ```
   `run.sh` setzt damit `ANTHROPIC_MODEL` UND `ANTHROPIC_DEFAULT_HAIKU_MODEL`
   (= Pin → keine Haiku-Hintergrundcalls) sowie `AGENT_EFFORT` im Agent-Job; der
   Entrypoint ruft zusaetzlich `--dangerously-skip-permissions` (headless). **Keine
   Temperatur** — Opus 4.8 lehnt Sampling-Parameter mit HTTP 400 ab; die Stochastik
   wird ueber pass^k gemessen.
2. **Image-Pinning (DZ5, bit-genau).** Images per Digest bauen/pushen; die exakten
   Digests des gewerteten Laufs stehen in [`../images/PINNING.md`](../images/PINNING.md):
   ```bash
   export IMAGE='<registry>/ubuntu-sshd@sha256:...'        # Target, gepinnt
   export AGENT_IMAGE='<registry>/claude-code@sha256:...'  # Agent, gepinnt
   ```
   Ohne Pin laeuft der ungepinnte Stand (ubuntu:24.04 + apt-at-runtime, agent
   `:latest`) — funktioniert, ist aber nicht bit-genau reproduzierbar.
3. **GT-Freeze.** Szenarien committet (GT-/state-/sudoers-/prompt-Hashes stehen pro
   Lauf pre-committed im Manifest). `git status` clean.
4. **Cluster + Secrets.** `kubectl get nodes` (beide Ready); Secrets `claude-oauth`,
   `otel-auth`, `forgejo-pull` im Namespace `grundschutz-lab`.

## Lauf

```bash
export AGENT_MODEL=claude-opus-4-8
export AGENT_EFFORT=high
export IMAGE='<registry>/ubuntu-sshd@sha256:...'        # gepinnt (PINNING.md)
export AGENT_IMAGE='<registry>/claude-code@sha256:...'  # gepinnt
scripts/hauptlauf.sh 4                                    # k=4 ueber alle Traeger
```

Der Lauf laeuft sequenziell (frischer Pod je Lauf, ~2–3 h). Sinnvoll im Hintergrund
fahren und stueckweise monitoren:
- Fortschritt: `ls runs/_index/*.tsv` + `kubectl -n grundschutz-lab get pods`.
- `run_item.sh` raeumt jeden Lauf selbst ab (kein Pod-Stau).

**Modell-/Effort-Pin verifizieren** (nach dem 1. Lauf): durch den Haiku-Pin
(`ANTHROPIC_DEFAULT_HAIKU_MODEL`) MUSS `modelUsage` genau **einen** Eintrag = den
Pin enthalten:
```bash
RID=$(ls -1dt runs/SYS.2.1.A18__compliant__* | head -1 | xargs basename)
jq -r '.modelUsage | keys[]' runs/$RID/agent_output.json   # nur claude-opus-4-8
```
Zeigt es Sonnet/Haiku, hat ein Pin nicht gegriffen → abbrechen und im gerenderten
`runs/$RID/agent-job.yaml` `ANTHROPIC_MODEL` + `ANTHROPIC_DEFAULT_HAIKU_MODEL`
pruefen. Effort/Permission stehen nicht im `modelUsage` → zusaetzlich `--effort high`
und `--dangerously-skip-permissions` im `runs/$RID/agent-job.yaml` bzw.
`agent_job.log` gegenpruefen.

## Auswertung

```bash
scripts/aggregate.py --json runs/_index/hauptlauf.json
```
Liefert:
- **pass^k je (Item × Variante × Ergebnisklasse)**,
- **3×3-Konfusionsmatrix** Soll × Ist,
- **Abstinenz-Rate** je Ergebnisklasse,
- **Telemetrie** (Kosten/Tokens/Dauer/Schritte).

Eine etwaige **Fehlerklassen-Zuordnung** ([`fehlerklassen.md`](fehlerklassen.md))
nicht bestandener Laeufe ist manuell/kodiert nachzutragen (aus `transcript.jsonl` +
`agent_output.json`); im gewerteten Set trat keiner auf. Figures/ICR leben im
Schwester-Repo `bsi-grundschutz-classification`.

## Urteils-Scoring (Hinweis)

`run_item.sh` extrahiert das Urteil heuristisch und auto-scored nur bei eindeutigem
Treffer (`sure=yes`). Unsichere Faelle (`sure=no`) bleiben ungescored (`phase=up`)
und sind manuell nachzutragen: `scripts/teardown.sh <run_id> --verdict <...>`. Bei
k=4 die Auto-Urteile gegen `agent_output.json` stichprobenartig gegenpruefen
(Auditierbarkeit).
