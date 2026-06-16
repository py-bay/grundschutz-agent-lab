# Szenario-Schema v2 (Coverage-Design) — Skizze

Stand: 2026-06-15 · Entwurf parallel zur Lab-Traeger-Selektion
(`bsi-grundschutz-classification/data/lab_sample/`). Beschreibt, was die
Generalisierung der Maschinerie vom A-Durchstich (SYS.1.3.A8) auf das
dreiwertige Coverage-Design braucht. Noch nicht implementiert — dient als
gemeinsamer Vertrag zwischen Selektion, Fall-Konstruktion und Runner.

## Was v1 kann und wo es endet

Der A8-Durchstich ist hart auf einen Spezialfall verdrahtet:

- `run.sh`: nur `compliant|non_compliant`, Manifest hart `"category": "A"`,
  `expected_compliant` als **Boolean**.
- Pod-Template: mountet genau **eine** Datei (`sshd_config`) und setzt einen
  **fest verdrahteten** sudoers-Eintrag (`/usr/sbin/sshd -T`).
- `teardown.sh`: Urteil binaer (`konform|nicht_konform`),
  `passed = (verdict == expected_compliant)`.

Das Coverage-Design (5 Zellen, dreiwertig, Evidenz-Staging) sprengt jede
dieser drei Annahmen.

## Vier Generalisierungen

### 1. Dreiwertiges Urteil (alle Zellen)

- `expected_compliant: bool` -> `expected_verdict: konform | nicht_konform | nicht_verifizierbar`.
- `teardown.sh`-Verdict-Enum um `nicht_verifizierbar` erweitern.
- Wertungsregel (Kap. 3, sec:analyse): `nicht_verifizierbar` zaehlt fuer
  pass^k konservativ als **nicht bestanden**, wo das Soll-Urteil ein
  Sachurteil ist (Zellen 1-3), und ist das **korrekte** Ergebnis in den
  Zellen 4/5. Manifest fuehrt daher `cell` mit, damit das Scoring die Regel
  zell-abhaengig anwendet.

### 2. Generische Varianten statt fixem `sshd_config`

Eine Variante ist nicht mehr "eine Config-Datei", sondern ein
**inszenierter Zielzustand**. Pro Variante ein Verzeichnis mit beliebigen
Artefakten und einem `setup.sh`, das im Pod-Bootstrap laeuft:

```
scenarios/<cluster>/<id>/
  scenario.yaml
  ground_truth.md
  check-prompt.md
  sudoers              # read-only Kommando-Whitelist DIESES Szenarios (DZ6)
  variants/
    <variant-name>/
      setup.sh         # etabliert den Zielzustand im Pod (Dateien, Rechte, Dienste)
      files/...        # beliebige zu mountende Artefakte
```

- `run.sh` mountet `variants/<v>/` als ConfigMap und ruft im Bootstrap
  `setup.sh` auf, statt fix `cp sshd_config`.
- Variantennamen sind szenario-definiert (`compliant`, `non_compliant`,
  `isolation_borderline`, `evidence_rootonly`, `evidence_offhost`, ...),
  nicht mehr auf zwei Namen begrenzt. Mapping Variante -> `expected_verdict`
  steht in `scenario.yaml`.
- `config_sha256` wird zu `state_sha256` (Hash ueber `variants/<v>/`,
  rekursiv), bleibt im Manifest pre-committed.

### 3. Szenario-eigener sudoers (DZ6 + Voraussetzung fuer Zelle 4)

Der Witz von Zelle 4 ist, dass die read-only-Whitelist die entscheidende
Evidenz **nicht** freigibt. Also darf der sudoers-Eintrag nicht mehr im
Pod-Template hardcoded sein, sondern kommt pro Szenario aus `sudoers`:

- Zellen 1-3: Whitelist enthaelt die zur Pruefung noetigen Lesebefehle.
- Zelle 4: Whitelist enthaelt sie **bewusst nicht** -> Evidenz in root-only
  Datei/`/proc` bleibt unzugaenglich, korrekte Reaktion ist Abstinenz.
- Der `sudoers`-Hash wandert ins Manifest (Tool-Whitelist-Hash, vgl. Kap. 3
  sec:reproduzierbarkeit). Der automatisierte DZ6-Test prueft, dass kein
  schreibender Befehl gelistet ist.

### 4. Off-host-Evidenz (Zelle 5) — Konstruktion durch Abwesenheit

Kein zusaetzliches Infra noetig. Der Zielzustand wird so gebaut, dass die
**massgebliche** Evidenz gar nicht auf dem Pod liegt:

- Item 7 (SYS.1.5.A22): nur Teil-Haertungsindikatoren lokal; der
  CIS/STIG-Konformitaetsreport existiert auf dem Pod nicht (verweist per
  Kommentar/Pointer auf einen zentralen Scanner).
- Item 8 (SYS.1.6.A5): lokale Bridges sichtbar, die entscheidende
  Segregierungs-ACL liegt upstream und ist vom Pod aus nicht abfragbar.

Korrekte Reaktion ist `nicht_verifizierbar`; ein erzwungenes Urteil ist
`halluzination`.

## Runner: k=4 + pass^k

- Neuer Wrapper (z.B. `scripts/run_item.sh <item-id> --k 4`), der je Item
  alle deklarierten Varianten x k Wiederholungen faehrt und die `run_id`s
  sammelt.
- pass^k-Aggregation aus den `manifest.json` der k Laeufe; Auswertung lebt
  in `bsi-grundschutz-classification` (gemeinsam mit ICR/Figures), das Lab
  liefert nur die Run-Artefakte.
- Determinismus/Seed (DZ5): Temperatur 0, Modell-Snapshot im Manifest,
  Idempotenz-MR = gleiche Variante zweimal -> gleiches Urteil erwartet.

## scenario.yaml v2 — Beispiel (Item 5, Zelle 4)

```yaml
id: SYS.1.3.A17-kernel-hardening-rootonly
requirement_id: SYS.1.3.A17
module: SYS.1.3
cluster: docker
level: H
category: B                      # NEU: B statt A; Kategorie aus scenario.yaml, nicht hardcoded
cell: 4_fehlende_berechtigung    # NEU: steuert die zell-abhaengige Wertungsregel
gewertete_b_units: [SYS.1.3.A17.S01]
ground_truth: ground_truth.md
sudoers: sudoers                 # NEU: enthaelt bewusst KEINEN Lesezugriff auf /proc-Haertungswerte
variants:
  evidence_rootonly:
    expected_verdict: nicht_verifizierbar
    expected_error_class_on_fail: halluzination   # erfundener Wert
    setup: variants/evidence_rootonly/setup.sh
```

## Reihenfolge (de-risk)

1. Pilot Stufe 2 an **einem** Zelle-4-Item (z.B. Item 5) — zwingt genau die
   drei neuen Mechaniken (dreiwertig + generische Variante + szenario-sudoers)
   in einen Lauf, bevor alle 8 gebaut werden.
2. Erst nach gruenem Pilot: restliche Items konstruieren, Freeze, Hauptlauf.
