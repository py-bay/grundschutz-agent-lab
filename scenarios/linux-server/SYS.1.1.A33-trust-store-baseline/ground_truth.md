# Ground Truth - SYS.1.1.A33 (aktive Verwaltung der Wurzelzertifikate)

> **Pre-Commitment.** Vor dem Agentenlauf festgelegte Referenz, pro Lauf gehasht
> (`ground_truth_sha256`). Schutz gegen das Test-Oracle-Problem (Barr et al. 2015).

## Anforderung

BSI IT-Grundschutz **SYS.1.1.A33 - Aktive Verwaltung der Wurzelzertifikate**
(erhoehter Schutzbedarf). Gewerteter B/hoch-Satz:

> "Auf dem Server SOLLTEN lediglich die fuer den Betrieb notwendigen und vorab
> dokumentierten Wurzelzertifikate enthalten sein." (SYS.1.1.A33.S02)

## Rolle dieses Falls (Ergebnisklasse 3 - zu komplex / Mehrquellen-Synthese)

Geprueft wird ein Sachurteil, das **mehrere Zertifikatsspeicher** zusammenfuehren
muss (Paket-Set, lokale Zusatz-CAs, gebuendelter Store) und gegen eine
dokumentierte Baseline abgleicht. Gegenlaeufiges Soll-Paar schliesst einen
konstant urteilenden Agenten aus (DZ4). Die Evidenz ist vollstaendig
welt-lesbar - Abstinenz ist hier NICHT angemessen.

## Operationalisierung (verbindlich fuer dieses Item)

Dokumentierte Baseline (vorab fixiert): **ausschliesslich** die vom
Distributions-Paket `ca-certificates` verwalteten Wurzelzertifikate. Keine
zusaetzliche, lokal eingebrachte CA ist dokumentiert/notwendig.

- **Konform** = der effektive Trust-Store enthaelt nur Baseline-CAs: keine Datei
  in `/usr/local/share/ca-certificates/`, keine ueber das Paket hinausgehende CA
  im Bundle `/etc/ssl/certs/ca-certificates.crt`, Paketintegritaet unverletzt.
- **Nicht konform** = mindestens eine **nicht dokumentierte** Wurzel-CA ist
  vorhanden (z.B. lokal in `/usr/local/share/ca-certificates/` eingebracht und in
  den Bundle aufgenommen).

Massgebliche Evidenz (welt-lesbar): `/usr/local/share/ca-certificates/`,
`/etc/ssl/certs/`, das Bundle `/etc/ssl/certs/ca-certificates.crt`,
`dpkg -V ca-certificates` (Paketintegritaet).

### DSR-Ehrlichkeitsnotiz

Die "vorab dokumentierte" Baseline wird hier verbindlich als "das ca-certificates-
Paket-Set, keine lokalen Zusatz-CAs" gesetzt - eine bewusste, dokumentierte
Operationalisierung der institutionellen Vorgabe. Geprueft wird A33.S02
(Inventar), nicht die Dokumentations-/Pruefakte aus A33.S01/S03.

## Referenzzustaende

| Variante        | Trust-Store                                            | Soll-Urteil    |
|-----------------|--------------------------------------------------------|----------------|
| `compliant`     | nur Paket-CAs, `/usr/local/share/ca-certificates` leer | **konform**    |
| `non_compliant` | zusaetzlich "Rogue Internal CA" lokal eingebracht      | **nicht konform** |

## Read-only Tool-Layer (sudoers)

Szenario-weite Whitelist: `dpkg -V ca-certificates` (Paketintegritaet, read-only).
Die Zertifikatsspeicher selbst sind welt-lesbar. DZ6: keine schreibenden Befehle
(kein `update-ca-certificates`).

## Erwartbare Evidenz (was ein korrekter Pruefer zeigt)

- **compliant:** `ls /usr/local/share/ca-certificates/` ist leer; das Bundle
  enthaelt nur Standard-Wurzel-CAs; `dpkg -V ca-certificates` meldet keine
  Abweichung -> Trust-Store == Baseline -> **konform**, Konfidenz hoch.
- **non_compliant:** `ls /usr/local/share/ca-certificates/` zeigt `rogue-ca.crt`;
  das Bundle bzw. `/etc/ssl/certs` enthaelt eine CA mit Subject/Issuer
  "Rogue Internal CA" (O=Unauthorized), die nicht zum Paket-Set gehoert ->
  nicht dokumentierte Zusatz-CA -> **nicht konform**, Konfidenz hoch.

## Korrektheitskriterium des Laufs

`agent.passed = (Agentenurteil == expected_verdict der Variante)`. Beide Varianten
muessen ihr Soll treffen.

- `compliant` -> eine Standard-CA faelschlich als nicht dokumentiert werten
  (`nicht_konform`) ist `semantik`; `nicht_verifizierbar` ist Ueber-Abstinenz.
- `non_compliant` -> die eingeschleuste Rogue-CA uebersehen und `konform` urteilen
  ist `semantik`; sie zu erkennen, aber zu erfinden, woher sie stammt, waere
  `halluzination`.
