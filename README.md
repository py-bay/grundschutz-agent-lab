# grundschutz-agent-lab

Reproduzierbarer Lab-Harness fuer die agentische Pruefung von
BSI-IT-Grundschutz-Anforderungen (SYS-Module). Teil der Bachelorarbeit
`bachelor_thesis`, aber als eigenstaendiges, reproduzierbares Artefakt
separat gehalten (Forgejo-gehostet).

Je Lauf zieht der Harness ein **ephemeres Ubuntu-SSH-Zielsystem** als
k3s-Pod hoch, etabliert einen definierten Referenzzustand, laesst einen
Agenten (Claude Code) das System **read-only per SSH** pruefen, gleicht das
**dreiwertige** Urteil gegen eine **pre-committed Ground Truth** ab und taggt
die Telemetrie pro Lauf.

> **Status (2026-06-16):** Schema **v2** (Coverage-Design). Maschinerie in
> Pilot Stufe 2 validiert (dreiwertiges Urteil, generische Varianten,
> szenario-eigener sudoers, Preflight-SSH, Agent-Isolation: 0 GT-Leakage).
> Validierter B-Fall: `SYS.2.3.A1` (Zelle 4, korrekte Abstinenz). Der
> A8-Durchstich (`SYS.1.3.A8`, Kategorie A) laeuft ueber einen Legacy-Zweig
> unveraendert weiter. Architektur: [`docs/architektur.md`](docs/architektur.md).

## Konzept in einem Satz

Das **Labor** ist das Forschungsartefakt, der **KI-Agent** der Pruefgegenstand.
Das Lab deckt den **Ergebnisraum** einer Pruefung ab (5 Szenario-Zellen:
konform / nicht konform / nicht verifizierbar, je korrekt -- plus sichtbare,
klassifizierbare Fehlerpfade). Begruendung: Thesis Kap. 3,
[`docs/design-principles.md`](docs/design-principles.md).

## Quickstart (v2)

Voraussetzungen am Operator-Host: `kubectl` mit gueltiger kubeconfig (ggf.
SSH-Tunnel zum k3s-API), `envsubst`, `openssl`, `ssh-keygen`, `claude`
(authentifiziert), Telemetrie ([`docs/telemetry.md`](docs/telemetry.md)).

```bash
# Variante hochziehen, Agenten fahren, Output sichern (alles in einem):
scripts/run.sh SYS.2.3.A1-sudo-config-rootonly locked --agent
#   -> Pod + ConfigMap + Secret + pre-committed Manifest, Preflight-SSH,
#      dann claude -p im isolierten CWD. Druckt run.id.

# Urteil festhalten + abraeumen (dreiwertig):
scripts/teardown.sh <run_id> --verdict nicht_verifizierbar --notes "..."
#   -> passed = (verdict == expected_verdict der Variante)
```

Adversarial-Paar je Traeger: eine Variante pro Soll-Urteil (z.B. `locked`
-> `nicht_verifizierbar`, `readable` -> `konform`). Ein Item gilt als
sauber, wenn alle Varianten ihr `expected_verdict` treffen.

Vollstaendiger manueller Durchlauf (auch ohne Tunnel, auf dem Node):
[`docs/runbook-durchspiel.md`](docs/runbook-durchspiel.md).

## Layout

```
scenarios/<gruppe>/<id>/        fachliches Szenario je Anforderung
  scenario.yaml                 Anforderung, category, cell, gewertete B-Saetze
  ground_truth.md               pre-committed Referenz (gehasht je Lauf)
  check-prompt.md               Agent-Prompt (dreiwertig, ohne GT-Leak)
  sudoers                       read-only Kommando-Whitelist dieses Szenarios (DZ6)
  variants/<v>/
    variant.env                 EXPECTED_VERDICT (+ erwartete Fehlerklasse)
    setup.sh                    etabliert den Zielzustand im Pod
kubernetes/                     namespace + getemplatetes On-demand-Pod-Manifest
images/ubuntu-sshd/             gepinntes Image fuer die echte Evaluation
scripts/run.sh                  Pod hoch + Stage + Manifest + Preflight + Agent
scripts/teardown.sh             Pod ab + dreiwertiges Urteil ins Manifest
runs/<run_id>/                  Lauf-Nachweis: manifest.json, agent_output.json,
                                transcript.jsonl, stage/, ggf. FINDING.md
docs/                           architektur, design-principles, scenario-schema-v2,
                                runbook, telemetry
```

Legacy-Szenarien mit nur `variants/<v>/sshd_config` (A8-Durchstich) laufen
ueber einen Abwaertskompatibilitaets-Zweig in `run.sh` weiter.

## Schema v1 -> v2

Generalisierung vom A-Durchstich aufs Coverage-Design: dreiwertiges Urteil,
Variante = inszenierter Zielzustand via `setup.sh`, read-only Whitelist pro
Szenario. Details: [`docs/scenario-schema-v2.md`](docs/scenario-schema-v2.md).

## Design in einem Satz

On-demand & imperativ (nicht ArgoCD, weil Reconcile gegen ephemere Pods
arbeitet); Ground-Truth-Pre-Commitment per Hash gegen das Test-Oracle-Problem;
Agent isoliert ohne GT-Zugriff; Telemetrie pro Lauf ueber `run.id` mit
OpenObserve verknuepft.

## Bezug zu den Repos

| Repo | Rolle |
|------|-------|
| `grundschutz-agent-lab` (dieses) | Lab: Szenarien, On-demand-Trigger, Run-Manifeste, Architektur |
| `bsi-grundschutz-classification` | Klassifikation/Auswertung + **Carrier-Selektion** (`data/lab_sample/`) |
| `bsi-grundschutz-parser` | Extraktion der Anforderungen (Anhang A) |
| `bachelor_thesis` | Text + massgebliche Methodik (Kap. 3) |
| `homelab` / `homelab-gitops` | k3s-Substrat / ArgoCD-Workloads (u.a. OpenObserve) |
