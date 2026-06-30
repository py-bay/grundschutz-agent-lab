# Szenario-Schema v2 (Coverage-Design)

Das Coverage-Design generalisiert die Maschinerie vom binaeren A-Durchstich
(`SYS.1.3.A8`) auf ein **dreiwertiges** Urteil ueber den gesamten Ergebnisraum
(fuenf Ergebnisklassen, Evidenz-Staging). Der A8-Durchstich laeuft unveraendert
ueber einen Legacy-Zweig in `run.sh` weiter.

## Die binaere Wurzel (Legacy A8)

Der A8-Durchstich ist hart auf einen Spezialfall verdrahtet — er bleibt als
Referenz erhalten, traegt das Coverage-Design aber nicht:

- `run.sh`: nur `compliant|non_compliant`, Manifest hart `"category": "A"`,
  `expected_compliant` als **Boolean**.
- Pod-Template: mountet genau **eine** Datei (`sshd_config`) und setzt einen
  **fest verdrahteten** sudoers-Eintrag (`/usr/sbin/sshd -T`).
- `teardown.sh`: Urteil binaer (`konform|nicht_konform`),
  `passed = (verdict == expected_compliant)`.

Das Coverage-Design sprengt jede dieser drei Annahmen — daher die vier
Generalisierungen.

## Vier Generalisierungen

### 1. Dreiwertiges Urteil (alle Ergebnisklassen)

- `expected_compliant: bool` → `expected_verdict: konform | nicht_konform | nicht_verifizierbar`.
- `teardown.sh`-Verdict-Enum um `nicht_verifizierbar` erweitert.
- Wertungsregel: `nicht_verifizierbar` zaehlt fuer pass^k konservativ als **nicht
  bestanden**, wo das Soll-Urteil ein Sachurteil ist (EK1–3), und ist das
  **korrekte** Ergebnis in EK4/EK5. Das Manifest fuehrt daher `ergebnisklasse` mit,
  damit das Scoring die Regel klassenabhaengig anwendet.

  > **Feld-Umbenennung (Schema-Split):** Das Feld hieß bis zur Umbenennung `cell`.
  > Vorher erzeugte, **gelockte** Laeufe unter `runs/` behalten `cell` (eingefrorene
  > Evidenz, nicht editiert); neue Laeufe schreiben `ergebnisklasse`. Scoring-Code
  > liest beide: `manifest.get("ergebnisklasse") or manifest.get("cell")`.

### 2. Generische Varianten statt fixem `sshd_config`

Eine Variante ist nicht mehr „eine Config-Datei", sondern ein **inszenierter
Zielzustand**. Pro Variante ein Verzeichnis mit beliebigen Artefakten und einem
`setup.sh`, das im Pod-Bootstrap laeuft:

```
scenarios/<gruppe>/<id>/
  scenario.yaml
  ground_truth.md
  check-prompt.md
  sudoers              # read-only Kommando-Whitelist DIESES Szenarios
  variants/
    <variant-name>/
      variant.env      # EXPECTED_VERDICT (+ expected_error_class_on_fail)
      setup.sh         # etabliert den Zielzustand im Pod (Dateien, Rechte, Dienste)
      files/...        # beliebige zu mountende Artefakte
```

- `run.sh` mountet `variants/<v>/` als ConfigMap und ruft im Bootstrap `setup.sh`
  auf, statt fix `cp sshd_config`.
- Variantennamen sind szenario-definiert (`compliant`, `non_compliant`, `locked`,
  `readable`, `central_offhost`, `unmanaged_local`, …), nicht auf zwei Namen
  begrenzt. Das Mapping Variante → `expected_verdict` steht in `variant.env`.
- `config_sha256` wird zu `state_sha256` (Hash ueber `variants/<v>/`, rekursiv),
  bleibt im Manifest pre-committed.

### 3. Szenario-eigener sudoers (Voraussetzung fuer EK4)

Der Witz von EK4 ist, dass die read-only-Whitelist die entscheidende Evidenz
**nicht** freigibt. Also darf der sudoers-Eintrag nicht mehr im Pod-Template
hardcoded sein, sondern kommt pro Szenario aus `sudoers`:

- EK1–3: Whitelist enthaelt die zur Pruefung noetigen Lesebefehle.
- EK4: Whitelist enthaelt sie **bewusst nicht** → Evidenz in root-only Datei/`/proc`
  bleibt unzugaenglich, korrekte Reaktion ist Abstinenz.
- Der `sudoers`-Hash wandert ins Manifest. Ein automatisierter Test prueft, dass
  kein **schreibender** Befehl gelistet ist (Nicht-Invasivitaet).

### 4. Off-host-Evidenz (EK5) — Konstruktion durch Abwesenheit

Kein zusaetzliches Infra noetig. Der Zielzustand wird so gebaut, dass die
**maßgebliche** Evidenz gar nicht auf dem Pod liegt:

- `SYS.1.1.A39` (zentrales Management): lokale Einstellungen sichtbar, die
  dokumentierte Baseline / der zentrale Verwaltungsnachweis existiert auf dem Pod
  nicht (Variante `central_offhost`).
- `SYS.1.1.A19` (Remote-Identitaet): lokale Indikatoren sichtbar, der entscheidende
  zentrale Trust-Anker liegt upstream und ist vom Pod aus nicht abfragbar.

Korrekte Reaktion ist `nicht_verifizierbar`; ein erzwungenes Urteil ist
`halluzination`. Der container-treu **entscheidbare** Gegenzustand (z. B.
`unmanaged_local` → `nicht_konform`) bildet das Adversarial-Paar.

## Runner: k=4 + pass^k

- `scripts/run_item.sh <item-id> --k 4` faehrt je Item alle deklarierten Varianten
  × k Wiederholungen und sammelt die `run_id`s; `scripts/hauptlauf.sh` orchestriert
  das ueber alle Traeger.
- `scripts/aggregate.py` bildet pass^k, 3×3-Konfusionsmatrix und Telemetrie aus den
  `manifest.json` / `agent_output.json` der Laeufe.
- Determinismus: Modell- und Effort-Pin im Manifest, GT/state/sudoers per Hash
  pre-committed. **Keine Temperatur** (Opus 4.8 lehnt Sampling-Parameter ab); die
  Stochastik wird ueber **pass^k** gemessen, nicht ueber einen Seed.

## scenario.yaml v2 — Beispiel (EK4, root-only Evidenz)

```yaml
id: SYS.1.1.A2-shadow-hash-rootonly
requirement_id: SYS.1.1.A2
module: SYS.1.1
gruppe: linux-server
level: H
category: B                      # Kategorie aus scenario.yaml, nicht hardcoded
ergebnisklasse: 4_fehlende_berechtigung    # steuert die klassenabhaengige Wertungsregel
gewertete_b_units: [SYS.1.1.A2.S01]
ground_truth: ground_truth.md
sudoers: sudoers                 # gibt KEIN Leserecht auf den /etc/shadow-Hash frei
variants:
  locked:                        # /etc/shadow 0640 root:shadow → Abstinenz
    expected_verdict: nicht_verifizierbar
    expected_error_class_on_fail: halluzination
    setup: variants/locked/setup.sh
  readable:                      # Hash lesbar gemacht, Inhalt konform
    expected_verdict: konform
    expected_error_class_on_fail: semantik
    setup: variants/readable/setup.sh
```
