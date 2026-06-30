# Hauptlauf-Ergebnisse (summativer k=4-Lauf)

Datum: 2026-06-24, beide Cluster-Nodes Ready.
Maschinenlesbar: [`../runs/_index/hauptlauf.json`](../runs/_index/hauptlauf.json)
(enthält die 40 Run-IDs des gewerteten Sets + alle Kennzahlen).

## Konfiguration (gepinnt)

| Parameter | Wert |
|---|---|
| Modell (Haupt + Hintergrund) | `claude-opus-4-8` (`ANTHROPIC_MODEL` + `ANTHROPIC_DEFAULT_HAIKU_MODEL`) |
| Reasoning-Effort | `high` (`claude -p --effort high`) |
| Permissions | `--dangerously-skip-permissions` (headless; Target read-only via sudoers) |
| Temperatur | n/a — Opus 4.8 lehnt Sampling-Params ab; Stochastik via pass^k gemessen |
| Agent-Image | `claude-code@sha256:238800d5…` (node-base gepinnt, claude-code 2.1.187) |
| Target-Image | `ubuntu-sshd@sha256:7176dbfe…` (ubuntu-base gepinnt) |
| Wiederholungen | k=4 je Variante; 5 Träger × 2 Varianten = **40 gewertete Läufe** |

`modelUsage` jedes Laufs enthält **ausschließlich** `claude-opus-4-8` (Hintergrund-
modell-Pin greift; kein Haiku). Über alle 40 Transcripts: **0 GT-Leakage** (DZ2).

## Kernergebnis: pass^k = 100 % über den gesamten Ergebnisraum

| Anforderung | Variante | EK | Soll | n | pass | pass^4 | Urteile |
|---|---|---|---|--:|--:|:--:|---|
| SYS.2.1.A18 | compliant | 1 | konform | 4 | 4 | **JA** | konform:4 |
| SYS.2.1.A18 | non_compliant | 2 | nicht_konform | 4 | 4 | **JA** | nicht_konform:4 |
| SYS.1.1.A33 | compliant | 3 | konform | 4 | 4 | **JA** | konform:4 |
| SYS.1.1.A33 | non_compliant | 3 | nicht_konform | 4 | 4 | **JA** | nicht_konform:4 |
| SYS.1.1.A2-authpolicy | compliant | 3 | konform | 4 | 4 | **JA** | konform:4 |
| SYS.1.1.A2-authpolicy | non_compliant | 3 | nicht_konform | 4 | 4 | **JA** | nicht_konform:4 |
| SYS.1.1.A2-shadow | readable | 4 | konform | 4 | 4 | **JA** | konform:4 |
| SYS.1.1.A2-shadow | locked | 4 | **nicht_verifizierbar** | 4 | 4 | **JA** | nicht_verifizierbar:4 |
| SYS.1.1.A39 | unmanaged_local | 5 | nicht_konform | 4 | 4 | **JA** | nicht_konform:4 |
| SYS.1.1.A39 | central_offhost | 5 | **nicht_verifizierbar** | 4 | 4 | **JA** | nicht_verifizierbar:4 |

**Alle 10 (Item×Variante)-Gruppen bestehen pass^4 vollständig** (40/40 gewertet,
0 unvollständig).

## 3×3-Konfusionsmatrix — perfekte Diagonale

| Soll ↓ \ Ist → | konform | nicht_konform | nicht_verifizierbar |
|---|--:|--:|--:|
| **konform** | 16 | 0 | 0 |
| **nicht_konform** | 0 | 16 | 0 |
| **nicht_verifizierbar** | 0 | 0 | 8 |

Null Off-Diagonal. Inklusive **korrekter Abstinenz**: EK4 `locked` 4/4 und EK5
`central_offhost` 4/4 → `nicht_verifizierbar` (gegatete bzw. off-host-abwesende
Evidenz). Das Lab diskriminiert sauber über EK1–5 **und** abstiniert dort, wo die
entscheidende Evidenz strukturell fehlt.

## Ergebnisklassen-Rollup

| EK | n | pass | Abstinenz (`nicht_verifizierbar`) |
|---|--:|--:|--:|
| 1 (sauber konform) | 4 | 100 % | 0 |
| 2 (sauber nicht_konform) | 4 | 100 % | 0 |
| 3 (zu komplex / Synthese) | 16 | 100 % | 0 |
| 4 (fehlende Berechtigung) | 8 | 100 % | **4** |
| 5 (nicht entscheidbar / off-host) | 8 | 100 % | **4** |

## Telemetrie, je Lauf über n=40

| Kennzahl | mean | median | min | max | Σ |
|---|--:|--:|--:|--:|--:|
| Kosten (USD) | 0,407 | 0,409 | 0,287 | 0,647 | **16,26** |
| Turns | 6,8 | 6 | 4 | 11 | 271 |
| Dauer (s) | 111 | 108 | 70 | 174 | 4 451 |
| Output-Tokens | 7 424 | 7 595 | 4 724 | 11 920 | 296 962 |
| Input-Tokens | 2 577 | 2 615 | 2 482 | 2 623 | 103 075 |
| Cache-Read-Tokens | 126 800 | 120 100 | 72 840 | 219 900 | 5 073 600 |

## Evidenzbasierte Auditierbarkeit

Stichprobe (3 Läufe) gegen `agent_output.json` + `transcript.jsonl`: jedes Urteil
ist durch reale Tool-Calls belegt (21/26/14 `tool_use` je Lauf), keine Behauptung
ohne Evidenz:
- A2-shadow `locked` → `getent group shadow`, `sudo stat /etc/shadow` (nur Metadaten)
  → Hash-Inhalt nicht lesbar → **Abstinenz** (korrekt, EK4).
- A39 `central_offhost` → `sudo -l` zeigt gegateten `cat baseline.expected`, Datei
  off-host abwesend → **Abstinenz** (korrekt, EK5).
- A33 `non_compliant` → `openssl x509` auf `rogue-ca.crt` (O=Unauthorized) →
  **nicht_konform** (korrekt).

## Dokumentierte Vorfälle (Transparenz)

1. **apt-`update`-Defekt (behoben, neu gefahren).** Ein erster Durchlauf von
   `SYS.1.1.A2-authpolicy/compliant` urteilte deterministisch 4/4 `nicht_konform`.
   Ursache war **kein** Modell- oder Szenariofehler im Sinne des Urteils, sondern
   ein **Tooling-Bug**: das gepinnte Target-Image löscht die apt-Listen, und der
   Bootstrap übersprang `apt-get update`, wenn `sshd` bereits vorhanden war →
   `setup.sh`-Install von `libpam-pwquality` scheiterte still (`|| true`) → das im
   PAM-Stack als `requisite` referenzierte Modul fehlte physisch → Zielzustand
   „compliant" war defekt. Opus 4.8 erkannte das **korrekt** (`nicht_konform`).
   Fix: `apt-get update` immer (commit), danach `SYS.1.1.A2-authpolicy` k=4 sauber
   neu (4/4 `konform`, 4/4 `nicht_konform`). Die kontaminierten Läufe (Index
   `…__110641Z__k4`) sind **nicht** Teil des gewerteten Sets.
2. **1 transienter API-Abbruch (ausgeschlossen, nachgefahren).** Ein A18/compliant-
   Lauf (`…__102842Z__0a18e7`) brach mit „API Error: Connection closed mid-response"
   ab (`is_error=true`, kein Urteil) — Infra-Rauschen (1/41 ≈ 2,4 %), kein
   Modellurteil. Ausgeschlossen, 1× nachgefahren (`konform`).

## Fehlerklassen

Im **gewerteten** 40er-Set gibt es **null Modell-Fehlurteile** → keine
Fehlerklassen-Zuordnung nötig. Die beiden Vorfälle oben sind als
Tooling-Defekt bzw. Infra-Transient klassifiziert, nicht als Modellfehler.

## Nebenbefund: stärkeres Modell ⇒ schärfere Diskriminierung

Den fehlenden `pam_pwquality`-Modul (Vorfall 1) urteilte Opus 4.8 **deterministisch
4/4** als `nicht_konform`, während der Pilot-Mix (Sonnet 4.6 + Haiku 4.5) dieselbe
defekte Konfiguration als `konform` durchwinkte. Das ist ein verwertbarer Beleg,
dass die Diskriminierungstiefe modellabhängig ist und ein stärkeres Modell reale
Wirksamkeitslücken (deklariert ≠ effektiv durchgesetzt) zuverlässiger aufdeckt —
zugleich hat es den Tooling-Bug überhaupt erst sichtbar gemacht.

## Provenienz

Gewertetes Set = die 40 Run-IDs in `runs/_index/hauptlauf.json` (`runs[]`).
Aggregation reproduzierbar via Symlink-Set:
`scripts/aggregate.py --runs-dir runs/_hauptlauf --json runs/_index/hauptlauf.json`
(das Set-Verzeichnis `runs/_hauptlauf/` ist gitignored; Quell-Runs liegen unter
`runs/<run_id>/`). Image-/Modell-Pins protokolliert in
[`../images/PINNING.md`](../images/PINNING.md).
