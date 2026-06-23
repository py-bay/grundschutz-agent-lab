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
Set): `SYS.2.3.A1` (EK4-Befund B2), `SYS.1.1.A19` (EK5-Befund P-05) - optional
separat als dokumentierte Befunde fahren.

## Vor dem Lauf (Pflicht)

1. **Entscheidung Modell** (DZ5/DZ9, Thesis-Aussage): Die Pilotlaeufe liefen auf
   dem claude-CLI-Default (**Sonnet 4.6 + Haiku 4.5-Mix**), NICHT auf Opus. Die
   Thesis nennt bislang "Opus 4.7" - aktuell ist **Opus 4.8**. Festlegen und pinnen:
   ```bash
   export AGENT_MODEL=claude-opus-4-8      # oder der gewaehlte Snapshot
   ```
   (run.sh setzt damit `ANTHROPIC_MODEL` im Agent-Job; ohne Pin laeuft der
   CLI-Default = nicht reproduzierbar.) Thesis-Kapitel 3/5 auf das gewaehlte
   Modell angleichen.
2. **Image-Pinning** (optional, DZ5 bit-genau; images/PINNING.md): Images per
   Digest bauen/pushen und
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
export AGENT_MODEL=claude-opus-4-8           # Pflicht
# ggf. IMAGE / AGENT_IMAGE pinnen
scripts/hauptlauf.sh 4                        # k=4 ueber alle sauberen Items
```

Der Lauf dauert lange (~2-3 h, sequenziell, frischer Pod je Lauf). Sinnvoll im
**Hintergrund** fahren und stueckweise monitoren:
- Fortschritt: `ls runs/_index/*.tsv` + `kubectl -n grundschutz-lab get pods`.
- run_item.sh raeumt jeden Lauf selbst ab (kein Pod-Stau).

**Modell-Pin verifizieren** (nach dem 1. Lauf): das gewaehlte Modell MUSS das
einzige genutzte sein:
```bash
RID=$(ls -1dt runs/SYS.2.1.A18__compliant__* | head -1 | xargs basename)
jq -r '.modelUsage | keys[]' runs/$RID/agent_output.json   # nur der Pin-Snapshot
```
Zeigt es Sonnet/Haiku, ist der Pin nicht gegriffen -> abbrechen, ANTHROPIC_MODEL
pruefen.

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

## Offene Entscheidungen

- Modell-Snapshot (Opus 4.8 vs. Thesis-"4.7") final festlegen + Thesis angleichen.
- Befund-Traeger A1/A19 in den Hauptlauf aufnehmen (als dokumentierte Befunde) oder
  nur in der Diskussion fuehren?
- Image-Pinning fuer den summativen Lauf ja/nein (Aufwand vs. DZ5-Strenge).
