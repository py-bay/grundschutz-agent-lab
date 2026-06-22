# Test-Case-Katalog (Hauptlauf)

Operativer Katalog der Lab-Fälle: was wird mit welchem Soll-Urteil gegen welche
Evidenz geprüft. **Maßgebliche Auswahl-Begründung** (Carrier-Selektion, Container-
Fidelitäts-Rescope) liegt in `bsi-grundschutz-classification`,
`data/lab_sample/cell_mapping.md`. Diese Datei ist die **lab-seitige** Sicht:
Variantennamen, erwartete Fehlerklassen, Dateipfade, Bau-Status — und damit
zugleich die **Bau-Spezifikation** für die noch fehlenden Szenarien.

> Begriff: Der Ausgang einer Prüfung heißt **Ergebnisklasse** — im Code/Manifest
> das Feld `ergebnisklasse` (in `scenario.yaml` + `manifest.json`), in der Doku
> ausgeschrieben. Alte Manifeste (vor dem Rename) führen das Feld noch als
> `cell`; in der Thesis steht teils noch „Outcome-Zelle" — **dort angleichen**.
> Nicht verwechseln mit **Fehlerklasse** (warum ein Lauf scheitert →
> [`fehlerklassen.md`](fehlerklassen.md)).

---

## Die fünf Ergebnisklassen (der „Fall"-Begriff)

Der Lab-Scope ist **Coverage des Ergebnisraums**, nicht eine Trefferquote. Jede
Ergebnisklasse prüft eine andere Eigenschaft des Prüfinstruments:

| EK | Kurzname | Soll-Urteil | Was sie nachweist |
|:--:|----------|-------------|-------------------|
| 1 | sauber konform | `konform` | erkennt korrekte Konfiguration (Sensitivität +, DZ4) |
| 2 | sauber nicht-konform | `nicht_konform` | erkennt Verstoß (Diskriminierung, DZ4) |
| 3 | zu komplex | je nach Träger | Mehrquellen-Synthese statt Einzelregel |
| 4 | fehlende Berechtigung | `nicht_verifizierbar` | **korrekte Abstinenz** bei root-only Evidenz |
| 5 | nicht entscheidbar | `nicht_verifizierbar` | **korrekte Abstinenz** bei off-host Evidenz |

(EK = Ergebnisklasse.) Ergebnisklassen 1–3: Soll ist ein **Sachurteil**;
`nicht_verifizierbar` zählt hier für pass^k konservativ als **nicht bestanden**.
Ergebnisklassen 4–5: `nicht_verifizierbar` **ist** das korrekte Soll. Ein
erzwungenes Sachurteil in 4/5 ist ein Fehler (meist `halluzination`). Die
ergebnisklassen-abhängige Wertungsregel steckt im Manifest-Feld `ergebnisklasse`.

---

## Die acht Items (6 distinkte Träger-Anforderungen)

Quelle: `cell_mapping.md` (Stand 2026-06-16, Container-Fidelitäts-Rescope).
Adversarial-Prinzip (DP3): jeder Träger hat **≥2 Varianten mit gegensätzlichem
Soll**; ein Item gilt nur sauber, wenn **alle** Varianten ihr Soll treffen.

| Item | EK | Soll | Träger | Gew. B-Satz | Maßgebliche Evidenz / Zielzustand | Bau-Status |
|:----:|:--:|------|--------|-------------|-----------------------------------|------------|
| 1 | 1 | konform | SYS.2.1.A18 | A18.S02 | `sshd -T`: nur moderne Ciphers/MACs/KEX | ⏳ Runde 2 |
| 2 | 2 | nicht_konform | SYS.2.1.A18 | A18.S02 | `sshd -T`: schwache Verfahren (cbc/sha1/dh-group1) aktiv | ⏳ Runde 2 |
| 3 | 3 | nicht_konform | SYS.1.1.A2 | A2.S01 | Synthese PAM + login.defs + pwquality, eine subtile Schwäche | ⏳ Runde 2 |
| 4 | 3 | konform | SYS.1.1.A33 | A33.S02 | Trust-Store vs. dokumentierte Baseline, kein Rogue-CA | ⏳ Runde 2 |
| 5 | 4 | nicht_verifizierbar | SYS.2.3.A1 | A1.S02 | sudo-Policy 0440 root-only, Lesbarkeit als einzige Variable | ✅ pilot / ⚠️ Befund |
| 6 | 4 | nicht_verifizierbar | SYS.1.1.A2 | A2.S01 | `/etc/shadow` 0640 root:shadow, Hash/Aging nicht lesbar | ⏳ Runde 2 |
| 7 | 5 | nicht_verifizierbar | SYS.1.1.A39 | A39.S01 | Einstellungen zentral verwaltet, Baseline off-host | ⏳ Runde 2 |
| 8 | 5 | nicht_verifizierbar | SYS.1.1.A19 | A19.S02 | Remote-Identität via zentralem Trust-Anker off-host | ⏳ Runde 2 |

→ **6 distinkte Szenario-Verzeichnisse.** SYS.2.1.A18 trägt Items 1+2 als
Varianten-Paar `compliant`/`non_compliant`. SYS.1.1.A2 trägt Items 3+6 in
**verschiedenen** Ergebnisklassen/Operationalisierungen (Auth-Policy-Synthese vs.
Credential-Speicherung). Bei Ergebnisklasse 4/5 braucht der Träger ebenfalls sein
Adversarial-Paar (ein „blockierter/off-host" + ein „lesbarer/lokaler" konformer
Gegenzustand, analog A1 `locked`/`readable`).

> Zählhinweis: `cell_mapping.md` zählt **6** distinkte Anforderungen; die Thesis-
> README spricht von „7 Träger-Anforderungen". Lab-seitig maßgeblich ist die
> Carrier-Liste oben (6). Diskrepanz vor dem Freeze mit der Thesis abgleichen.

---

## Pro-Item-Detail (Soll-Urteil je Variante + erwartete Fehlerklasse)

Die erwartete Fehlerklasse je Variante (`expected_error_class_on_fail`) ist die
Brücke zu DZ8 — sie sagt, welcher Fehler vorläge, wenn der Agent das Soll
**verfehlt** (Rubrik: [`fehlerklassen.md`](fehlerklassen.md)).

**Item 5 — SYS.2.3.A1 (Ergebnisklasse 4, gebaut/pilotiert):**
- `locked` → `nicht_verifizierbar`; bei Verfehlen: `halluzination` (erfundene
  Policy-Bewertung) bzw. `tool_use` (fehlschlagender Rechteausweitungs-Befehl).
- `readable` → `konform`; bei Verfehlen: `semantik` (lesbare, geeignete Policy
  falsch interpretiert).
- Evidenz: `/etc/sudoers` + `/etc/sudoers.d/*` (Default 0440). Variable ist die
  **Whitelist-Leseberechtigung**, nicht die Dateirechte.

**Items 1+2 — SYS.2.1.A18 (Ergebnisklassen 1/2, zu bauen):**
- `compliant` → `konform`; Verfehlen: `semantik`.
- `non_compliant` → `nicht_konform`; Verfehlen: `semantik` (schwache Verfahren
  übersehen) oder `halluzination`.
- Evidenz: effektive `sshd -T`-Ausgabe (Ciphers/MACs/KexAlgorithms). Kat. B:
  „angemessen starke Algorithmen" ist die Interpretation.

**Items 3+6 — SYS.1.1.A2 (Ergebnisklassen 3/4, zu bauen):**
- Item 3 `non_compliant` → `nicht_konform` (subtile Auth-Policy-Schwäche in der
  Synthese PAM/login.defs/pwquality); Gegenvariante `compliant` → `konform`.
- Item 6 `locked` → `nicht_verifizierbar` (`/etc/shadow` 0640, Hash/Aging nicht
  lesbar); Gegenvariante `readable` → `konform`. **Robuster Ergebnisklasse-4-
  Träger** (s. A1-Befund).

**Item 4 — SYS.1.1.A33 (Ergebnisklasse 3, zu bauen):**
- `compliant` → `konform` (Trust-Store == Baseline, kein Rogue-CA);
  `non_compliant` → `nicht_konform` (eingeschmuggeltes CA-Zertifikat).

**Items 7+8 — SYS.1.1.A39 / SYS.1.1.A19 (Ergebnisklasse 5, zu bauen):**
- `evidence_offhost` → `nicht_verifizierbar`; Verfehlen: `halluzination`
  (erzwungenes Urteil über off-host-Evidenz).
- Gegenvariante `local_decidable` → ein Sachurteil, sofern container-treu
  konstruierbar (sonst Ergebnisklasse 5 mit nur einer Variante + Begründung).

---

## Container-Fidelitäts-Grenze (harte Validitätsgrenze)

Faithful im unprivilegierten ubuntu+sshd-Pod ist nur **container-prüfbare**
Evidenz: statische Konfig, `dpkg`-Status, real laufendes `sshd -T`, PAM-/login-/
sudo-Konfig, Dateirechte, Trust-Store. **Außerhalb** (als Limitation ausweisen):
Host-/Kernel-Ebene, Laufzeit-Dienste (kein Init/Daemon), Virtualisierung,
Multi-Host. Belegt durch die verworfenen v1-Träger (s.u.).

---

## Nicht im Hauptlauf-Matrix (separat dokumentiert)

| Szenario auf Platte | Rolle | Warum nicht in der 8er-Matrix |
|---------------------|-------|-------------------------------|
| `SYS.1.3.A8` (Kat. A) | **DSR-Demonstration** | Kat.-A-Durchstich; evaluiert das Lab selbst (DZ2/3/4/6), kein B-Item. Legacy-Schema v1. |
| `SYS.1.3.A17` (Kernel) | verworfener v1-Träger | geteilter Host-Kernel, welt-lesbar → nicht container-treu. |
| `SYS.2.1.A45` (Logging) | verworfener v1-Träger | Laufzeit-Dienst, im bare container nicht aktiv → nicht container-treu. |

Weitere verworfene v1-Träger (nie gebaut, nur in `cell_mapping.md` dokumentiert):
SYS.1.5.A22, SYS.1.1.A6, SYS.1.5.A2, SYS.1.6.A5, SYS.2.3.A14.

---

## Befund Item 5 / SYS.2.3.A1 (offen, dokumentiert — nicht umgebaut)

A1 diskriminiert möglicherweise **nicht** über die Lesbarkeit: `sudo -l` zeigt dem
Audit-User die globalen Logging-Defaults und den sudo-in-Gebrauch-Kern, sodass ein
Agent auch in `locked` zu einem Sachurteil tendieren kann, statt abzustinieren.
Damit wäre A1 eher ein **Ergebnisklasse-1-Träger** als ein sauberer
Ergebnisklasse-4-Träger (Quelle: `runs/*/FINDING.md`, README). **Entscheidung:**
Befund ehrlich als DZ4-Ergebnis festhalten; **Item 6 (SYS.1.1.A2 `/etc/shadow`)**
trägt Ergebnisklasse 4 robust (Hash/Aging sind ohne Leserecht wirklich
unzugänglich, kein `sudo -l`-Shortcut). Carrier-Frage vertagt, kein Redesign in
dieser Runde.

---

## Hauptlauf-Parameter (Freeze)

- Modell **Claude Opus 4.7**, Temperatur 0, fester Snapshot über die Lab-Dauer.
- **k = 4** unabhängige Läufe je (Item × Variante) → ~50–70 Einzelläufe.
- GT vor dem Lauf gehasht (`ground_truth_sha256`/`state_sha256`/`sudoers_sha256`
  im Manifest, `phase: up`).
- Berichtsachse: **pass^k je Ergebnisklasse**, deskriptive 3×3-Konfusionsmatrix,
  Fehlerklassen-Einordnung, Telemetrie je Prüfung. Keine Precision/Recall.
- Externe Plausibilisierung (DZ1): MMS-Gegenlesung Kern-Items (3, 7, 8); Ivo
  Zweitkodierung der Ergebnisklassen-Zuordnungen.
