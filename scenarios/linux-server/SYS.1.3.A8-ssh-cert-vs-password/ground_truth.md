# Ground Truth - SYS.1.3.A8 (SSH: Zertifikat statt Passwort)

> **Pre-Commitment.** Dieses Dokument ist die *vor* dem Agentenlauf
> festgelegte Referenz. Sein SHA-256-Hash wird pro Lauf in
> `runs/<run_id>/manifest.json` festgeschrieben (Schutz gegen das
> Test-Oracle-Problem, Barr et al. 2015). Aenderungen nach einem Lauf
> sind nur als protokollierte, neu gehashte Revision zulaessig - nie
> stillschweigend.

## Anforderung

BSI IT-Grundschutz **SYS.1.3.A8 - Verschluesselter Zugriff ueber Secure
Shell** (Standard, SOLLTE). Relevanter Teilsatz:

> "Fuer die Authentifizierung SOLLTEN vorrangig Zertifikate anstatt
> eines Passworts verwendet werden."

## Operationalisierung (verbindlich fuer diesen Prototyp)

Die Anforderung wird auf eine binaere, technisch ablesbare Pruefgroesse
reduziert (Kategorie A):

- **konform** genau dann, wenn die *effektive* sshd-Konfiguration
  `PasswordAuthentication no` **und** `PubkeyAuthentication yes` meldet.
- **nicht konform**, sobald `PasswordAuthentication yes` (Passwort-Login
  moeglich).

Effektivkonfiguration heisst: Ergebnis von `sudo sshd -T`, nicht der
blosse Inhalt von `/etc/ssh/sshd_config` - Drop-ins unter
`/etc/ssh/sshd_config.d/*.conf` koennen Werte ueberschreiben.

### DSR-Ehrlichkeitsnotiz zur Operationalisierung

Der A8-Wortlaut ist mit "vorrangig" interpretativ weicher als die hier
gewaehlte harte Schwelle. Die Reduktion auf "Passwort-Login deaktiviert"
ist eine bewusste, dokumentierte Setzung fuer den Prototyp und keine
erschoepfende Auslegung von A8 (z.B. bleiben Zertifikats- vs. blosse
Schluesselauthentisierung und Algorithmen-Haertung aussen vor). Fuer die
spaetere eigentliche Evaluation (B-Anforderungen) ist die
Operationalisierung pro Anforderung erneut zu begruenden.

## Referenzzustaende

| Variante        | sshd (effektiv)                                  | Ground Truth   | Erwartetes Urteil |
|-----------------|--------------------------------------------------|----------------|-------------------|
| `compliant`     | PasswordAuthentication no, PubkeyAuthentication yes | **konform**    | konform / PASS    |
| `non_compliant` | PasswordAuthentication yes                        | **nicht konform** | nicht konform / FAIL |

Die Variantendateien liegen unter `variants/<variante>/sshd_config` und
gehen unveraendert in den Pod (gemountete ConfigMap -> `/etc/ssh/sshd_config`).

## Erwartbare Evidenz (was ein korrekter Pruefer zeigt)

- `sudo sshd -T | grep -i passwordauthentication` -> `passwordauthentication no` (compliant) bzw. `... yes` (non_compliant)
- ergaenzend `pubkeyauthentication yes`
- Begruendung des Urteils gegen genau diese Effektivwerte.

## Korrektheitskriterium des Laufs

`agent.passed = (Agentenurteil == erwartetes Urteil der Variante)`.
Ein Lauf ist nur dann ein erfolgreicher Smoke-Test, wenn *beide*
Varianten korrekt klassifiziert werden (konform UND nicht konform),
sonst koennte ein konstant antwortender Agent zufaellig "bestehen".
