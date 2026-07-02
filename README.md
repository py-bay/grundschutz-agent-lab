# grundschutz-agent-lab

Reproduzierbarer Lab-Harness fuer die agentische Pruefung von
BSI-IT-Grundschutz-Anforderungen (SYS-Module). Begleitartefakt einer
Bachelorarbeit, als eigenstaendiges, reproduzierbares Repository gehalten.

Je Lauf zieht der Harness ein **ephemeres Ubuntu-SSH-Zielsystem** als
k3s-Pod hoch, etabliert einen definierten Referenzzustand, laesst einen
Agenten (Claude Code) das System **read-only per SSH** pruefen, gleicht das
**dreiwertige** Urteil (`konform` / `nicht_konform` / `nicht_verifizierbar`)
gegen eine **pre-committed Ground Truth** ab und taggt die Telemetrie pro Lauf.

## Konzept in einem Satz

Das **Labor** ist das Forschungsartefakt, der **KI-Agent** der Pruefgegenstand.
Das Lab deckt den **Ergebnisraum** einer Pruefung ab — fuenf Ergebnisklassen
(EK1 sauber konform, EK2 sauber nicht-konform, EK3 zu komplex / Mehrquellen-
Synthese, EK4 fehlende Berechtigung, EK5 nicht entscheidbar / off-host), jede
mit eigenem Soll-Urteil und sichtbaren, klassifizierbaren Fehlerpfaden.

## Ergebnis des summativen Laufs

Hauptlauf auf `claude-opus-4-8` (effort `high`), k=4 je Variante, 5 Traeger
x 2 Varianten = **40 gewertete Laeufe**: **pass⁴ = 100 %** ueber alle zehn
(Item x Variante)-Gruppen, fehlerfreie 3x3-Konfusionsmatrix inklusive korrekter
Abstinenz in EK4/EK5, **0 GT-Leakage** ueber alle 40 Transkripte. Zahlen und
Matrix in [`docs/hauptlauf-ergebnisse.md`](docs/hauptlauf-ergebnisse.md),
maschinenlesbar in [`runs/_index/hauptlauf.json`](runs/_index/hauptlauf.json).

## Quickstart (Agent in-cluster)

Voraussetzungen: `kubectl` mit gueltiger kubeconfig (der Operator kann auf
einem Node laufen, **kein Laptop noetig**), `envsubst`, `openssl`, `ssh-keygen`.
Einmal im Namespace `grundschutz-lab` anzulegen: Secret `claude-oauth`
(OAuth-Token aus `claude setup-token`); bei aktivem Telemetrie-Export zusaetzlich
`otel-auth` (OTel-Header, siehe [`docs/telemetry.md`](docs/telemetry.md)) und bei
privater Registry ein Pull-Secret (Default-Name `forgejo-pull`).
Agent-Image aus `images/claude-code/` bauen und in eine vom Cluster erreichbare
Registry pushen.

**Reproduktion auf einem fremden Cluster:** Das Lab laeuft auf jedem
Kubernetes-Cluster. Node-Pinning, Telemetrie-Senke und Pull-Secret sind per
Env uebersteuerbar (Substrat-Vertrag in `scripts/lib.sh`); die Schritte stehen
in [`docs/hauptlauf-runbook.md`](docs/hauptlauf-runbook.md#reproduktion-auf-einem-fremden-cluster).
Der niedrigschwelligste Einstieg braucht **gar keinen Cluster**: `--target docker`
faehrt das Zielsystem als lokalen Docker-Container, `--agent` den Agenten lokal
(`claude`-CLI genuegt), `--backend opencode` einen vollstaendig lokalen offenen
Stack (opencode + Ollama, siehe
[`docs/agent-backend-opencode-lokal.md`](docs/agent-backend-opencode-lokal.md)).

```bash
# Variante hochziehen, Agenten als k8s-Job IN-CLUSTER fahren, Output sichern:
scripts/run.sh SYS.1.1.A2-shadow-hash-rootonly readable --agent-incluster
#   -> Pod + ConfigMap + Secret + Service + pre-committed Manifest, Preflight-SSH,
#      dann claude als Job im Cluster (kein Repo-/GT-Mount). Druckt run.id.

# Urteil festhalten + abraeumen (dreiwertig):
scripts/teardown.sh <run_id> --verdict konform --notes "..."
#   -> passed = (verdict == expected_verdict der Variante)
```

`--agent` statt `--agent-incluster` faehrt `claude` als **Dev-Fallback lokal**
auf dem Operator (isoliertes `/tmp`-CWD), ohne Image/Secrets.

Adversarial-Paar je Traeger: eine Variante pro Soll-Urteil (z. B. `locked`
-> `nicht_verifizierbar`, `readable` -> `konform`). Ein Item gilt als sauber,
wenn **alle** Varianten ihr `expected_verdict` treffen.

Summativer k=4-Lauf ueber alle Traeger + Auswertung:
[`docs/hauptlauf-runbook.md`](docs/hauptlauf-runbook.md).

## Layout

```
scenarios/<gruppe>/<id>/        fachliches Szenario je Anforderung
  scenario.yaml                 Anforderung, category, ergebnisklasse, gewertete B-Saetze
  ground_truth.md               pre-committed Referenz (gehasht je Lauf)
  check-prompt.md               Agent-Prompt (dreiwertig, ohne GT-Leak)
  sudoers                       read-only Kommando-Whitelist dieses Szenarios
  variants/<v>/
    variant.env                 EXPECTED_VERDICT (+ erwartete Fehlerklasse)
    setup.sh                    etabliert den Zielzustand im Pod
kubernetes/                     namespace + getemplatetes On-demand-Pod-Manifest
images/                         gepinnte Images (Dockerfiles + PINNING.md)
scripts/run.sh                  Pod hoch + Stage + Manifest + Preflight + Agent
scripts/run_item.sh             ein Item x alle Varianten x k Wiederholungen
scripts/hauptlauf.sh            kompletter summativer Lauf ueber alle Traeger
scripts/teardown.sh             Pod ab + dreiwertiges Urteil ins Manifest
scripts/aggregate.py            pass^k + Konfusionsmatrix + Telemetrie ueber ein Lauf-Set
runs/<run_id>/                  Lauf-Nachweis: manifest.json, agent_output.json,
                                transcript.jsonl, ggf. FINDING.md
runs/_index/hauptlauf.json      maschinenlesbares Ergebnis des gewerteten 40er-Sets
docs/                           Schema, Test-Case-Katalog, Runbook, Fehlerklassen,
                                Hauptlauf-Ergebnisse, Telemetrie
```

Legacy-Szenarien mit nur `variants/<v>/sshd_config` (A8-Durchstich, binaeres
Urteil) laufen ueber einen Abwaertskompatibilitaets-Zweig in `run.sh` weiter.

## Schema & Faelle

Eine Variante ist ein **inszenierter Zielzustand** (via `setup.sh`), nicht eine
Config-Datei; das Urteil ist dreiwertig; die read-only Whitelist gilt **pro
Szenario** (Voraussetzung fuer EK4: die entscheidende Evidenz wird bewusst nicht
freigegeben). Schema-Details: [`docs/scenario-schema-v2.md`](docs/scenario-schema-v2.md).
Die Faelle des gewerteten Sets — Soll-Urteil je Variante, erwartete Fehlerklasse,
maßgebliche Evidenz: [`docs/test-case-katalog.md`](docs/test-case-katalog.md).

## Design in einem Satz

On-demand & imperativ (nicht ArgoCD, weil Reconcile gegen ephemere Pods
arbeitet); Ground-Truth-Pre-Commitment per Hash gegen das Test-Oracle-Problem;
Agent isoliert ohne GT-Zugriff (0 GT-Leakage); Telemetrie pro Lauf ueber
`run.id` mit OpenObserve verknuepft.

## Bezug zu den Schwester-Repos

| Repo | Rolle |
|------|-------|
| `grundschutz-agent-lab` (dieses) | Lab: Szenarien, On-demand-Trigger, Run-Manifeste, Ergebnisse |
| [`bsi-grundschutz-classification`](https://github.com/py-bay/bsi-grundschutz-classification) | Klassifikation/Auswertung + Carrier-Selektion |
| [`bsi-grundschutz-parser`](https://github.com/py-bay/bsi-grundschutz-parser) | Extraktion der Anforderungen aus den BSI-Bausteinen |

Das Cluster-Substrat des gewerteten Laufs (2-Knoten-k3s) ist nicht Teil der
Veroeffentlichung und nicht erforderlich: Das Lab setzt nur den dokumentierten
Substrat-Vertrag voraus (beliebiger k8s-Cluster, s. Quickstart/Runbook).

## Lizenz und BSI-Quellenhinweis

Der Inhalt dieses Repositories steht unter der [MIT-Lizenz](LICENSE).

Die Szenarien zitieren einzelne Anforderungssaetze aus dem
**IT-Grundschutz-Kompendium des BSI (Edition 2023)** mit Anforderungs-ID als
Kurzzitate (Quelle: [BSI, IT-Grundschutz-Kompendium](https://www.bsi.bund.de/DE/Themen/Unternehmen-und-Organisationen/Standards-und-Zertifizierung/IT-Grundschutz/it-grundschutz_node.html),
(c) Bundesamt fuer Sicherheit in der Informationstechnik). Die Baustein-PDFs
selbst werden nicht weiterverteilt.
