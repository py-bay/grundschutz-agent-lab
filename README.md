# grundschutz-agent-lab

Reproduzierbarer Lab-Harness fuer die prototypische, agentische Pruefung
von BSI-IT-Grundschutz-Anforderungen (SYS-Module). Teil der Bachelorarbeit
`bachelor_thesis`, aber als eigenstaendiges, reproduzierbares Artefakt
separat gehalten (Forgejo-gehostet, analog `homelab-gitops`).

Es zieht je Lauf ein **ephemeres Ubuntu-SSH-Zielsystem** als k3s-Pod hoch,
spielt einen definierten Referenzzustand ein, laesst einen Agenten
(Claude Code) das System read-only per SSH pruefen, gleicht das Urteil
gegen eine **pre-committed Ground Truth** ab und taggt die Telemetrie pro
Lauf.

> **Status:** Demonstration/Smoke-Test (DSR-Schritt 5), noch nicht die
> eigentliche Evaluation. Erste Anforderung: **SYS.1.3.A8** (Kategorie A,
> SSH Zertifikat statt Passwort). Begruendung in
> [`docs/methodology.md`](docs/methodology.md).

## Quickstart

Vollstaendiger Durchlauf inkl. der Variante **ohne Tunnel (auf dem k3s-Node
per Web-Terminal)**: [`docs/runbook-durchspiel.md`](docs/runbook-durchspiel.md).

Voraussetzungen auf dem Betreiber-Laptop: `kubectl` mit gueltiger
kubeconfig (ggf. SSH-Tunnel zum k3s-API), `envsubst`, `openssl`,
`ssh-keygen`, sowie aktivierte Claude-Code-Telemetrie
([`docs/telemetry.md`](docs/telemetry.md)). Auf dem Node laeuft stattdessen
`k3s kubectl` (von den Scripts automatisch erkannt).

```bash
# 1) Konformes Zielsystem hochziehen
scripts/run.sh SYS.1.3.A8-ssh-cert-vs-password compliant
# -> druckt run.id, SSH-Zugang und das fertige `claude`-Kommando

# 2) Agent laufen lassen (Kommando aus der Ausgabe kopieren) ...

# 3) Abraeumen + Urteil festhalten
scripts/teardown.sh <run_id> --verdict konform --notes "sshd -T zeigte passwordauthentication no"

# 4) Gegenprobe mit dem nicht-konformen Zustand
scripts/run.sh SYS.1.3.A8-ssh-cert-vs-password non_compliant
# ... Agent ... teardown mit --verdict nicht_konform
```

Ein Smoke-Test gilt als bestanden, wenn der Agent **beide** Varianten
korrekt klassifiziert (`agent.passed=true` in beiden Manifesten).

## Layout

```
scenarios/<gruppe>/<id>/      fachliches Szenario je Anforderung
  scenario.yaml               Schema (Anforderung, Kategorie, Operationalisierung)
  ground_truth.md             pre-committed Referenz (gehasht je Lauf)
  check-prompt.md             Agent-Prompt (ohne GT-Leak)
  variants/<v>/sshd_config    konformer / nicht-konformer Zustand
kubernetes/                   namespace + getemplatetes On-demand-Pod-Manifest
images/ubuntu-sshd/           gepinntes Image fuer die echte Evaluation
scripts/run.sh                Trigger: Pod hoch + Manifest + Port-Forward
scripts/teardown.sh           Pod ab + Urteil ins Manifest
runs/<run_id>/manifest.json   Lauf-Nachweis (auswertbar ueber Laeufe)
docs/                         Methodik (DSR) + Telemetrie
```

## Design in einem Satz

On-demand & imperativ (nicht ArgoCD, weil Reconcile gegen ephemere Pods
arbeitet); Ground-Truth-Pre-Commitment per Hash gegen das Test-Oracle-
Problem; Telemetrie pro Lauf ueber `run.id` mit OpenObserve verknuepft.
