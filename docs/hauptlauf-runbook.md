# Hauptlauf-Runbook (summativer k=4-Lauf)

Schritt-fuer-Schritt fuer den summativen Hauptlauf. Pilot + Durchfuehrbarkeit sind
nachgewiesen (docs/pilot-runde2.md): 5 saubere, agent-validierte Traeger ueber den
Ergebnisraum EK1-5. Dieses Runbook fixiert nur den summativen Lauf + Auswertung.

## Traeger-Set (sauber, agent-validiert)

| Item-ID | Ergebnisklasse(n) | Varianten |
|---------|-------------------|-----------|
| `SYS.2.1.A18-ssh-crypto-strength` | 1 + 2 | compliant / non_compliant |
| `SYS.1.1.A33-trust-store-baseline` | 3 | compliant / non_compliant |
| `SYS.1.1.A2-authpolicy-synthesis` | 3 | compliant / non_compliant |
| `SYS.1.1.A2-shadow-hash-rootonly` | 4 | locked / readable |
| `SYS.1.1.A39-central-mgmt-offhost` | 5 | central_offhost / unmanaged_local |

= 5 Items x 2 Varianten x k=4 = **40 Laeufe**. Befund-Traeger (nicht im sauberen
Set): `SYS.2.3.A1` (EK4-Befund B2), `SYS.1.1.A19` (EK5-Befund P-05) - **NICHT**
mitlaufen lassen (Entscheidung 2026-06), nur in der Diskussion (Kap. 5/6) fuehren.

## Vor dem Lauf (Pflicht)

1. **Modell + Effort + Permissions (DZ5/DZ9, festgelegt 2026-06):** Die Pilotlaeufe
   liefen auf dem claude-CLI-Default (**Sonnet 4.6 + Haiku 4.5-Mix**), NICHT auf Opus.
   Festgelegt fuer den Hauptlauf:
   ```bash
   export AGENT_MODEL=claude-opus-4-8      # Haupt- UND Hintergrundmodell (Haiku-Pin)
   export AGENT_EFFORT=high                # claude -p --effort high (lib.sh-Default)
   ```
   run.sh setzt damit `ANTHROPIC_MODEL` UND `ANTHROPIC_DEFAULT_HAIKU_MODEL` (= Pin ->
   keine Haiku-Hintergrundcalls) sowie `AGENT_EFFORT` im Agent-Job; der Entrypoint
   ruft zusaetzlich `--dangerously-skip-permissions` (Bypass, headless). **KEINE
   Temperatur** (Opus 4.8 lehnt Sampling-Params mit 400 ab). **Thesis Kap. 3/5 von
   „Opus 4.7" auf „Opus 4.8" angleichen** und „Temperatur 0" streichen
   (-> effort + pass^k). Da der Entrypoint geaendert wurde, ist der **Agent-Image-
   Rebuild Pflicht** (Punkt 2).
2. **Image-Pinning** (beschlossen: ja, DZ5 bit-genau; images/PINNING.md). Der
   Agent-Image-Rebuild ist ohnehin Pflicht (geaenderter Entrypoint: effort +
   Permission-Bypass). Images per Digest bauen/pushen und
   ```bash
   export IMAGE='git.k3s.pybay.de/gitsim/ubuntu-sshd@sha256:...'
   export AGENT_IMAGE='git.k3s.pybay.de/gitsim/claude-code@sha256:...'
   ```
   Ohne Pin laeuft der Pilot-Stand (ubuntu:24.04 + apt-at-runtime, agent :latest) -
   funktioniert, ist aber nicht bit-genau reproduzierbar.
3. **GT-Freeze:** Szenarien committet (die GT-/state-/sudoers-/prompt-Hashes
   stehen pro Lauf pre-committed im Manifest). Stand pruefen: `git status` clean.
4. **Tunnel + Secrets:** `kubectl get nodes` (beide Ready); Secrets `claude-oauth`,
   `otel-auth`, `forgejo-pull` im NS `grundschutz-lab`.

## Lauf

```bash
export AGENT_MODEL=claude-opus-4-8           # Haupt- + Hintergrundmodell
export AGENT_EFFORT=high                      # Reasoning-Effort (Default high)
export IMAGE='git.k3s.pybay.de/gitsim/ubuntu-sshd@sha256:...'        # gepinnt (PINNING.md)
export AGENT_IMAGE='git.k3s.pybay.de/gitsim/claude-code@sha256:...'  # gepinnt; Rebuild Pflicht
scripts/hauptlauf.sh 4                        # k=4 ueber alle sauberen Items
```

Der Lauf dauert lange (~2-3 h, sequenziell, frischer Pod je Lauf). Sinnvoll im
**Hintergrund** fahren und stueckweise monitoren:
- Fortschritt: `ls runs/_index/*.tsv` + `kubectl -n grundschutz-lab get pods`.
- run_item.sh raeumt jeden Lauf selbst ab (kein Pod-Stau).

**Modell-/Effort-Pin verifizieren** (nach dem 1. Lauf): durch den Haiku-Pin
(`ANTHROPIC_DEFAULT_HAIKU_MODEL`) MUSS `modelUsage` genau EINEN Eintrag = den Pin
enthalten:
```bash
RID=$(ls -1dt runs/SYS.2.1.A18__compliant__* | head -1 | xargs basename)
jq -r '.modelUsage | keys[]' runs/$RID/agent_output.json   # nur claude-opus-4-8
```
Zeigt es Sonnet/Haiku, hat ein Pin nicht gegriffen -> abbrechen und im gerenderten
`runs/$RID/agent-job.yaml` `ANTHROPIC_MODEL` + `ANTHROPIC_DEFAULT_HAIKU_MODEL`
pruefen. Effort/Permission werden NICHT im modelUsage sichtbar -> zusaetzlich
`--effort high` und `--dangerously-skip-permissions` im `runs/$RID/agent-job.yaml`
bzw. `agent_job.log` gegenpruefen.

## Auswertung

```bash
scripts/aggregate.py --json runs/_index/hauptlauf.json
```
Liefert fuer Kapitel 5:
- **pass^k je (Item x Variante x Ergebnisklasse)** (DZ5),
- **3x3-Konfusionsmatrix** Soll x Ist (DZ4),
- **Abstinenz-Rate** je Ergebnisklasse,
- **Telemetrie** (Kosten/Tokens/Dauer/Schritte, DZ7).

Die **Fehlerklassen-Zuordnung** (DZ8, docs/fehlerklassen.md) der nicht bestandenen
Laeufe ist manuell/kodiert nachzutragen (aus transcript.jsonl + agent_output.json).
Figures/ICR leben in `bsi-grundschutz-classification`.

## Urteils-Scoring (Hinweis)

`run_item.sh` extrahiert das Urteil heuristisch und auto-scored nur bei
eindeutigem Treffer (`sure=yes`). Unsichere Faelle (`sure=no`) bleiben ungescored
(`phase=up`) und sind manuell nachzutragen:
`scripts/teardown.sh <run_id> --verdict <...>`. Bei k=4 die Auto-Urteile gegen
`agent_output.json` stichprobenartig gegenpruefen (DZ3-Auditierbarkeit).

## Entschiedene Punkte (2026-06)

- **Modell:** `claude-opus-4-8` (Thesis Kap. 3/5 von „4.7" angleichen; kein dat. Snapshot).
- **Effort:** `high`. **Permissions:** `--dangerously-skip-permissions` (Bypass, headless).
- **Hintergrundmodell:** `ANTHROPIC_DEFAULT_HAIKU_MODEL=claude-opus-4-8` (keine Haiku-Calls).
- **Keine Temperatur** (Opus 4.8 lehnt Sampling-Params ab) — „Temperatur 0" aus Thesis/PINNING gestrichen.
- **Image-Pinning:** ja (Digests); Agent-Image-Rebuild wegen Entrypoint-Aenderung ohnehin Pflicht.
- **Befund-Traeger A1 (EK4) / A19 (EK5):** NICHT mitlaufen — nur in der Diskussion (Kap. 5/6) fuehren.

> Vor dem Rebuild: exakte CLI-Flag-Namen (`--effort`, `--dangerously-skip-permissions`)
> und das Hintergrundmodell-Env (`ANTHROPIC_DEFAULT_HAIKU_MODEL`) mit `claude --help`
> der gepinnten CLI-Version verifizieren; danach am 1. Lauf gegenpruefen (s. oben).
