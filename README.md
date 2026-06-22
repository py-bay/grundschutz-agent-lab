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

> **Status (2026-06-19):** Schema **v2** (Coverage-Design). Maschinerie
> validiert -- **Agent laeuft in-cluster als k8s-Job, laptop-frei**
> (dreiwertiges Urteil, generische Varianten, szenario-/variant-eigener sudoers,
> Preflight-SSH, Agent-Isolation via Dateisystem/Mount: 0 GT-Leakage). Sauber
> validiert: `SYS.2.3.A1` Variante `readable` -> `konform`. **Befund:** A1
> diskriminiert nicht ueber die Lesbarkeit (sichtbarer sudo+Logging-Kern via
> `sudo -l`) und ist damit ein **Ergebnisklasse-1-Traeger, kein Ergebnisklasse-4-Traeger** (siehe
> `FINDING.md` im jeweiligen `runs/`-Verzeichnis). Der A8-Durchstich
> (`SYS.1.3.A8`, Kategorie A) laeuft ueber einen Legacy-Zweig weiter.
> Architektur: [`docs/architektur.md`](docs/architektur.md).

## Konzept in einem Satz

Das **Labor** ist das Forschungsartefakt, der **KI-Agent** der Pruefgegenstand.
Das Lab deckt den **Ergebnisraum** einer Pruefung ab (5 Ergebnisklassen:
konform / nicht konform / nicht verifizierbar, je korrekt -- plus sichtbare,
klassifizierbare Fehlerpfade). Begruendung: Thesis Kap. 3,
[`docs/design-principles.md`](docs/design-principles.md).

## Quickstart (v2, Agent in-cluster)

Voraussetzungen: `kubectl` mit gueltiger kubeconfig (Operator kann auf einem
Node laufen, **kein Laptop noetig**), `envsubst`, `openssl`, `ssh-keygen`.
Einmal im Namespace `grundschutz-lab` anzulegen: Secrets `claude-oauth`
(OAuth-Token aus `claude setup-token`), `otel-auth` (OTel-Header,
[`docs/telemetry.md`](docs/telemetry.md)), `forgejo-pull` (Registry-Pull).
Agent-Image aus `images/claude-code/` bauen und in die Forgejo-Registry pushen.

```bash
# Variante hochziehen, Agenten als k8s-Job IN-CLUSTER fahren, Output sichern:
scripts/run.sh SYS.2.3.A1-sudo-config-rootonly readable --agent-incluster
#   -> Pod + ConfigMap + Secret + Service + pre-committed Manifest, Preflight-SSH,
#      dann claude als Job im Cluster (kein Repo-/GT-Mount). Druckt run.id.

# Urteil festhalten + abraeumen (dreiwertig):
scripts/teardown.sh <run_id> --verdict konform --notes "..."
#   -> passed = (verdict == expected_verdict der Variante)
```

`--agent` statt `--agent-incluster` faehrt `claude` als **Dev-Fallback lokal**
auf dem Operator (isoliertes `/tmp`-CWD), ohne Image/Secrets.

Adversarial-Paar je Traeger: eine Variante pro Soll-Urteil (z.B. `locked`
-> `nicht_verifizierbar`, `readable` -> `konform`). Ein Item gilt als
sauber, wenn alle Varianten ihr `expected_verdict` treffen.

Vollstaendiger manueller Durchlauf (auch ohne Tunnel, auf dem Node):
[`docs/runbook-durchspiel.md`](docs/runbook-durchspiel.md).

## Layout

```
scenarios/<gruppe>/<id>/        fachliches Szenario je Anforderung
  scenario.yaml                 Anforderung, category, ergebnisklasse, gewertete B-Saetze
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
