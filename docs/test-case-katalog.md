# Test-Case-Katalog (Hauptlauf)

Operativer Katalog der gewerteten Lab-Faelle: was wird mit welchem Soll-Urteil
gegen welche Evidenz geprueft. Die Carrier-Selektion (welche Anforderung welche
Ergebnisklasse traegt, inkl. Container-Fidelitaets-Rescope) liegt im Schwester-
Repo `bsi-grundschutz-classification`; diese Datei ist die **lab-seitige** Sicht:
Variantennamen, erwartete Fehlerklassen, maßgebliche Evidenz.

> **Ergebnisklasse ≠ Fehlerklasse.** Die **Ergebnisklasse** (EK1–5, Feld
> `ergebnisklasse` in `scenario.yaml` + `manifest.json`) ist der erwartete Ausgang
> einer Pruefung. Die **Fehlerklasse** sagt, *wodurch* ein Lauf das Soll verfehlt
> haette (→ [`fehlerklassen.md`](fehlerklassen.md)); sie wird nur fuer nicht
> bestandene Laeufe vergeben. Alte, vor einer Feld-Umbenennung erzeugte Manifeste
> unter `runs/` fuehren `ergebnisklasse` teils noch als `cell` (eingefrorene
> Evidenz, nicht editiert); Auswertungscode liest beide Schluessel.

---

## Die fuenf Ergebnisklassen (der „Fall"-Begriff)

Der Lab-Scope ist **Coverage des Ergebnisraums**, nicht eine Trefferquote. Jede
Ergebnisklasse prueft eine andere Eigenschaft des Pruefinstruments:

| EK | Kurzname | Soll-Urteil | Was sie nachweist |
|:--:|----------|-------------|-------------------|
| 1 | sauber konform | `konform` | erkennt korrekte Konfiguration (Sensitivitaet) |
| 2 | sauber nicht-konform | `nicht_konform` | erkennt Verstoß (Diskriminierung) |
| 3 | zu komplex | je nach Variante | Mehrquellen-Synthese statt Einzelregel |
| 4 | fehlende Berechtigung | `nicht_verifizierbar` | **korrekte Abstinenz** bei root-only Evidenz |
| 5 | nicht entscheidbar | `nicht_verifizierbar` | **korrekte Abstinenz** bei off-host Evidenz |

EK1–3: das Soll ist ein **Sachurteil**; `nicht_verifizierbar` zaehlt hier fuer
pass^k konservativ als **nicht bestanden**. EK4–5: `nicht_verifizierbar` **ist**
das korrekte Soll; ein erzwungenes Sachurteil ist ein Fehler (meist
`halluzination`). Die ergebnisklassen-abhaengige Wertungsregel steckt im
Manifest-Feld `ergebnisklasse`.

---

## Das gewertete Traeger-Set (5 Anforderungen, 10 Item×Variante-Gruppen)

Adversarial-Prinzip: jeder Traeger hat **≥2 Varianten mit gegensaetzlichem Soll**;
ein Item gilt nur sauber, wenn **alle** Varianten ihr Soll treffen. Alle zehn
Gruppen bestehen pass⁴ = 100 % (→ [`hauptlauf-ergebnisse.md`](hauptlauf-ergebnisse.md)).

| EK | Anforderung | Variante | Soll | Gew. B-Satz | Maßgebliche Evidenz / Zielzustand |
|:--:|-------------|----------|------|-------------|-----------------------------------|
| 1 | SYS.2.1.A18 | compliant | konform | A18.S02 | `sshd -T`: nur moderne Ciphers/MACs/KEX |
| 2 | SYS.2.1.A18 | non_compliant | nicht_konform | A18.S02 | `sshd -T`: schwache Verfahren (cbc/sha1/dh-group1) aktiv |
| 3 | SYS.1.1.A33 | compliant | konform | A33.S02 | Trust-Store == dokumentierte Baseline, kein Rogue-CA |
| 3 | SYS.1.1.A33 | non_compliant | nicht_konform | A33.S02 | eingeschmuggeltes CA-Zertifikat (O=Unauthorized) |
| 3 | SYS.1.1.A2-authpolicy | compliant | konform | A2.S01 | Synthese PAM + login.defs + pwquality, durchgaengig stark |
| 3 | SYS.1.1.A2-authpolicy | non_compliant | nicht_konform | A2.S01 | dieselbe Synthese mit einer subtilen Schwaeche |
| 4 | SYS.1.1.A2-shadow | readable | konform | A2.S01 | `/etc/shadow` lesbar gemacht, Hash/Aging konform |
| 4 | SYS.1.1.A2-shadow | locked | nicht_verifizierbar | A2.S01 | `/etc/shadow` 0640 root:shadow, Hash/Aging nicht lesbar |
| 5 | SYS.1.1.A39 | unmanaged_local | nicht_konform | A39.S01 | Einstellungen lokal, nicht zentral verwaltet (entscheidbar) |
| 5 | SYS.1.1.A39 | central_offhost | nicht_verifizierbar | A39.S01 | zentral verwaltet, Baseline off-host abwesend |

SYS.2.1.A18 traegt EK1+EK2 als Paar `compliant`/`non_compliant`. SYS.1.1.A2 traegt
**zwei** Traeger in verschiedenen Ergebnisklassen/Operationalisierungen
(`-authpolicy` = Auth-Policy-Synthese EK3, `-shadow` = Credential-Speicherung EK4).

---

## Pro-Traeger-Detail (Soll je Variante + erwartete Fehlerklasse)

Die erwartete Fehlerklasse je Variante (`expected_error_class_on_fail`) ist die
Bruecke zur Diagnostik: sie sagt, welcher Fehler vorlaege, wenn der Agent das Soll
**verfehlt** (Rubrik: [`fehlerklassen.md`](fehlerklassen.md)). Im gewerteten Set
trat **kein** Fehlurteil auf, also keine Zuordnung — die Spalte ist die ex-ante
Hypothese je Fall.

**SYS.2.1.A18 (EK1/EK2):** `compliant` → `konform`, `non_compliant` →
`nicht_konform`. Evidenz: effektive `sshd -T`-Ausgabe (Ciphers/MACs/KexAlgorithms).
Kat. B: „angemessen starke Algorithmen" ist die zu treffende Interpretation.
Verfehlen: `semantik` (schwache Verfahren als stark eingeordnet) bzw. `halluzination`.

**SYS.1.1.A33 (EK3):** `compliant` → `konform` (Trust-Store == Baseline),
`non_compliant` → `nicht_konform` (eingeschmuggeltes CA-Zertifikat). Verfehlen:
`semantik`.

**SYS.1.1.A2-authpolicy (EK3):** `compliant` → `konform`, `non_compliant` →
`nicht_konform` (subtile Schwaeche in der Synthese aus PAM/login.defs/pwquality).
Verfehlen: `semantik`.

**SYS.1.1.A2-shadow (EK4):** `locked` → `nicht_verifizierbar` (`/etc/shadow` 0640,
Hash/Aging ohne Leserecht wirklich unzugaenglich — kein `sudo -l`-Shortcut);
`readable` → `konform` (Lesbarkeit als einzige Variable, Inhalt konform). Verfehlen
`locked`: `halluzination` (erfundene Bewertung) bzw. `tool_use` (fehlschlagender
Rechteausweitungs-Befehl); Verfehlen `readable`: `semantik`.

**SYS.1.1.A39 (EK5):** `central_offhost` → `nicht_verifizierbar` (maßgebliche
Baseline liegt off-host, vom Pod nicht abfragbar); `unmanaged_local` → `nicht_konform`
(container-treu entscheidbarer Gegenzustand: lokal verwaltet statt zentral).
Verfehlen `central_offhost`: `halluzination` (erzwungenes Urteil ueber off-host-Evidenz).

---

## Befund-Traeger (dokumentiert, **nicht** im gewerteten Set)

Zwei Traeger sind aus dem Set genommen und nur als Befund gefuehrt (Quelle:
`runs/*/FINDING.md`):

- **SYS.2.3.A1 (EK4-Befund):** A1 diskriminiert **nicht** ueber die Lesbarkeit —
  `sudo -l` zeigt dem Audit-User die globalen Logging-Defaults und den
  sudo-in-Gebrauch-Kern, sodass der Agent auch in `locked` zu einem Sachurteil
  tendiert statt abzustinieren. Damit ist A1 eher ein EK1- als ein sauberer
  EK4-Traeger. **SYS.1.1.A2-shadow** traegt EK4 robust und ersetzt A1 im Set.
- **SYS.1.1.A19 (EK5-Befund):** als off-host-Traeger gefuehrt, im Pilot pilotiert,
  aus dem gewerteten Set genommen; SYS.1.1.A39 traegt EK5.

---

## Container-Fidelitaets-Grenze (harte Validitaetsgrenze)

Faithful im unprivilegierten ubuntu+sshd-Pod ist nur **container-pruefbare**
Evidenz: statische Konfig, `dpkg`-Status, real laufendes `sshd -T`, PAM-/login-/
sudo-Konfig, Dateirechte, Trust-Store. **Außerhalb** (als Limitation auszuweisen):
Host-/Kernel-Ebene, Laufzeit-Dienste (kein Init/Daemon im bare Container),
Virtualisierung, Multi-Host. Belegt durch die verworfenen v1-Traeger (s. u.).

---

## Nicht in der Hauptlauf-Matrix (separat dokumentiert)

| Szenario auf Platte | Rolle | Warum nicht im gewerteten Set |
|---------------------|-------|-------------------------------|
| `SYS.1.3.A8` (Kat. A) | **DSR-Demonstration** | Kat.-A-Durchstich; evaluiert das Lab selbst, kein B-Item. Legacy-Schema v1, binaeres Urteil. |
| `SYS.1.3.A17` (Kernel) | verworfener v1-Traeger | geteilter Host-Kernel, welt-lesbar → nicht container-treu. |
| `SYS.2.1.A45` (Logging) | verworfener v1-Traeger | Laufzeit-Dienst, im bare Container nicht aktiv → nicht container-treu. |
| `SYS.2.3.A1` / `SYS.1.1.A19` | Befund-Traeger | s. o. — dokumentiert, aus dem Set genommen. |

---

## Hauptlauf-Parameter (Freeze)

- Modell **`claude-opus-4-8`** (Haupt- und Hintergrundmodell gepinnt), Reasoning-
  Effort **`high`**, headless `--dangerously-skip-permissions` (Target read-only via
  sudoers). **Keine Temperatur** — Opus 4.8 lehnt Sampling-Parameter ab, die
  Stochastik wird ueber **pass^k** gemessen.
- **k = 4** unabhaengige Laeufe je (Item × Variante) → 5 Traeger × 2 Varianten =
  **40 gewertete Laeufe**.
- GT vor dem Lauf gehasht (`ground_truth_sha256` / `state_sha256` / `sudoers_sha256`
  im Manifest, `phase: up`).
- Berichtsachse: **pass^k je Ergebnisklasse**, deskriptive 3×3-Konfusionsmatrix,
  Fehlerklassen-Einordnung, Telemetrie je Pruefung. Keine Precision/Recall.
- Image-Pins (Digests) protokolliert in [`../images/PINNING.md`](../images/PINNING.md).
