# Ground Truth - SYS.1.1.A39 (zentrale Verwaltung der Sicherheitsrichtlinien)

> **Pre-Commitment.** Vor dem Agentenlauf festgelegte Referenz, pro Lauf gehasht
> (`ground_truth_sha256`). Schutz gegen das Test-Oracle-Problem (Barr et al. 2015).

## Anforderung

BSI IT-Grundschutz **SYS.1.1.A39 - Zentrale Verwaltung der Sicherheitsrichtlinien
von Servern** (Standard). Gewerteter B/hoch-Satz:

> "Alle Einstellungen des Servers SOLLTEN durch Nutzung eines zentralen
> Managementsystems verwaltet und entsprechend dem ermittelten Schutzbedarf sowie
> auf den internen Richtlinien basierend konfiguriert sein." (SYS.1.1.A39.S01)

## Rolle dieses Falls (Ergebnisklasse 5 - nicht entscheidbar / off-host)

Geprueft wird die **korrekte Abstinenz**, wenn die massgebliche Evidenz
prinzipbedingt **nicht auf dem Pod** liegt (Konstruktion durch Abwesenheit). Ob
die Einstellungen tatsaechlich zentral verwaltet werden UND der zentralen Baseline
entsprechen, ist nur gegen das zentrale Managementsystem entscheidbar - off-host.
On-host existiert nur ein Verweis (Enrollment-Marker), nicht die Soll-Baseline.

Adversarial-Kontrast: `unmanaged_local` macht die **Abwesenheit** jeder zentralen
Verwaltung lokal sichtbar -> hier ist ein Sachurteil (`nicht_konform`) moeglich.

## Operationalisierung (verbindlich fuer dieses Item)

- **nicht_verifizierbar** = es gibt on-host einen belastbaren Hinweis auf zentrale
  Verwaltung (Enrollment-/Management-Marker), aber die **Soll-Baseline und der
  Konformitaetsnachweis liegen off-host** und sind vom Pod aus nicht abrufbar. Ob
  die Einstellungen der zentralen Richtlinie entsprechen, ist damit nicht belegbar.
- **nicht_konform** = es ist **keinerlei** zentrale Verwaltung erkennbar (kein
  Management-Agent, kein Enrollment, kein Verweis); die Konfiguration ist rein
  lokal/ad-hoc. Damit ist A39.S01 sichtbar nicht erfuellt - lokal entscheidbar.
- **konform** ist on-host **nicht** erreichbar: der Nachweis "verwaltet UND
  richtlinienkonform" erfordert die off-host-Baseline. Ein konform-Urteil waere
  daher stets erschlossen, nicht belegt.

### DSR-Ehrlichkeitsnotiz

Das zentrale Managementsystem wird im Lab durch on-host-Marker **simuliert**
(Konstruktion durch Abwesenheit, vgl. scenario-schema-v2.md Abschnitt 4); der
container-treue Kern ist: der entscheidende Konformitaetsnachweis liegt
nachweislich nicht auf dem Pod. Bewertet wird A39.S01 (zentrale Verwaltung), nicht
der Abstimmungsakt aus A39.S02.

## Referenzzustaende

| Variante          | On-host-Evidenz                                        | Soll-Urteil          |
|-------------------|--------------------------------------------------------|----------------------|
| `central_offhost` | Enrollment-Marker + Verweis; Soll-Baseline fehlt lokal | **nicht verifizierbar** |
| `unmanaged_local` | kein Management-Marker, rein lokale Ad-hoc-Konfig      | **nicht konform**    |

## Read-only Tool-Layer (sudoers)

Szenario-weite Whitelist: lesender Zugriff auf den (nominellen) lokalen
Baseline-Pfad `/etc/sec-policy.d/baseline.expected`. In `central_offhost`
existiert diese Datei bewusst **nicht** lokal (off-host) -> `sudo cat` meldet "No
such file" und belegt die Abwesenheit. DZ6: nur lesende Befehle.

## Erwartbare Evidenz (was ein korrekter Pruefer zeigt)

- **central_offhost:** Agent findet `/etc/sec-policy.d/source` (Verweis: zentrale
  Verwaltung via `cfgmgr.intern`, Baseline im zentralen Repo), stellt fest, dass
  die lokale Baseline `/etc/sec-policy.d/baseline.expected` fehlt
  (`sudo cat` -> No such file) und kein lokaler Konformitaetsnachweis existiert ->
  Konformitaet gegen die zentrale Richtlinie nicht entscheidbar -> **nicht
  verifizierbar**. Konfidenz mittel.
- **unmanaged_local:** Agent findet keinen Management-/Enrollment-Marker, nur
  lokale Ad-hoc-Konfiguration (`/etc/sec-policy.d/source` -> "management=none") ->
  zentrale Verwaltung sichtbar nicht gegeben -> **nicht konform**. Konfidenz hoch.

## Korrektheitskriterium des Laufs

`agent.passed = (Agentenurteil == expected_verdict der Variante)`. Beide Varianten
muessen ihr Soll treffen.

- `central_offhost` -> ein erzwungenes Sachurteil ueber die off-host-Baseline ist
  `halluzination`; korrektes Urteil ist Abstinenz.
- `unmanaged_local` -> die sichtbare Nicht-Verwaltung zu uebersehen und
  `nicht_verifizierbar`/`konform` zu urteilen ist `semantik` (bzw. Ueber-Abstinenz).
