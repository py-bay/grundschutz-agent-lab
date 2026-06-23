# Ground Truth - SYS.1.1.A2 (Authentisierung, lokale Passwort-Policy)

> **Pre-Commitment.** Vor dem Agentenlauf festgelegte Referenz, pro Lauf gehasht
> (`ground_truth_sha256`). Schutz gegen das Test-Oracle-Problem (Barr et al. 2015).

## Anforderung

BSI IT-Grundschutz **SYS.1.1.A2 - Authentisierung an Servern** (Basis).
Gewerteter B/hoch-Satz:

> "Fuer die Anmeldung von Benutzenden und Diensten am Server MUESSEN
> Authentisierungsverfahren eingesetzt werden, die dem Schutzbedarf der Server
> angemessen sind." (SYS.1.1.A2.S01)

## Rolle dieses Falls (Ergebnisklasse 3 - zu komplex / Mehrquellen-Synthese)

Zweite Operationalisierung von A2.S01 (neben dem shadow-Item, Ergebnisklasse 4):
hier die **lokale Passwort-Policy** als Sachurteil, das mehrere welt-lesbare
Quellen zusammenfuehren muss. Gegenlaeufiges Soll-Paar schliesst einen konstant
urteilenden Agenten aus (DZ4). Die Evidenz ist vollstaendig lesbar - Abstinenz
ist NICHT angemessen.

## Operationalisierung (verbindlich fuer dieses Item)

Angemessen (= konform) genau dann, wenn die Passwort-Policy **wirksam durchgesetzt**
ist - nicht nur deklariert. Quellen-Synthese:
- `/etc/security/pwquality.conf`: ausreichende Mindestlaenge/Komplexitaet, UND
- `/etc/pam.d/common-password`: diese Policy ist **tatsaechlich eingebunden**
  (`pam_pwquality.so` im Stack) bzw. `pam_unix.so` erzwingt `minlen`, plus
  zeitgemaesses Hash-Verfahren (`yescrypt`), UND
- `/etc/login.defs`: sinnvolle Alterung (`PASS_MAX_DAYS` nicht 99999), kein
  Schwachverfahren; kein `nullok` in `common-auth`.

Nicht konform = die Policy ist **nur deklariert, aber wirkungslos**: eine starke
`pwquality.conf`, die **nicht** in den PAM-Stack eingebunden ist, waehrend
`pam_unix.so` ohne `minlen`/Komplexitaet laeuft -> es greift faktisch keine
Laengen-/Komplexitaetsdurchsetzung. Die Schwaeche ist nur durch den Abgleich
pwquality.conf <-> common-password erkennbar (Synthese).

### DSR-Ehrlichkeitsnotiz

Reduktion von "angemessen" auf "wirksam durchgesetzte Passwort-Policy" ist eine
bewusste, dokumentierte Setzung (container-treuer Kern). Der Fokus liegt auf der
**Wirksamkeit** (eingebunden vs. nur deklariert), nicht auf einer bestimmten
Schwellenwahl.

## Referenzzustaende

| Variante        | Passwort-Policy                                          | Soll-Urteil    |
|-----------------|---------------------------------------------------------|----------------|
| `compliant`     | pwquality stark UND eingebunden + pam_unix minlen        | **konform**    |
| `non_compliant` | pwquality stark, aber NICHT eingebunden, pam_unix ohne minlen | **nicht konform** |

In beiden: `nullok` entfernt, sane login.defs-Alterung, yescrypt - die einzige
Variable ist die **Wirksamkeit** der deklarierten Komplexitaets-/Laengen-Policy.

## Read-only Tool-Layer (sudoers)

Die massgebliche Evidenz (`/etc/pam.d/*`, `/etc/login.defs`,
`/etc/security/pwquality.conf`) ist welt-lesbar; privilegierter Zugriff ist nicht
noetig. Whitelist daher minimal (ein harmloser Lesebefehl). DZ6: nur lesend.

## Erwartbare Evidenz (was ein korrekter Pruefer zeigt)

- **compliant:** Agent liest `pwquality.conf` (minlen=14 + credits), sieht in
  `common-password` die Zeile `pam_pwquality.so` (Policy eingebunden) sowie
  `pam_unix.so ... yescrypt minlen=14`, und in `login.defs` sane Alterung -> die
  Policy ist wirksam -> **konform**, Konfidenz hoch.
- **non_compliant:** Agent liest dieselbe starke `pwquality.conf`, stellt aber im
  `common-password`-Stack fest, dass `pam_pwquality.so` **fehlt** und `pam_unix.so`
  **ohne** `minlen` laeuft -> die deklarierte Policy greift nicht -> **nicht
  konform**, Konfidenz hoch. Wer allein aus der starken `pwquality.conf` auf
  konform schliesst, verfehlt die Synthese.

## Korrektheitskriterium des Laufs

`agent.passed = (Agentenurteil == expected_verdict der Variante)`. Beide Varianten
muessen ihr Soll treffen.

- `compliant` -> die wirksame Policy faelschlich als schwach werten ist `semantik`;
  `nicht_verifizierbar` ist Ueber-Abstinenz (Evidenz ist lesbar).
- `non_compliant` -> die nicht eingebundene (wirkungslose) Policy fuer wirksam
  halten und `konform` urteilen ist `semantik`.
