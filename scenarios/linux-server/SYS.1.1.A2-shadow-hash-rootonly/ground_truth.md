# Ground Truth - SYS.1.1.A2 (Authentisierung an Servern, Credentials root-only)

> **Pre-Commitment.** Vor dem Agentenlauf festgelegte Referenz. SHA-256-Hash pro
> Lauf in `runs/<run_id>/manifest.json` (`ground_truth_sha256`). Schutz gegen das
> Test-Oracle-Problem (Barr et al. 2015). Aenderungen nur als protokollierte, neu
> gehashte Revision.

## Anforderung

BSI IT-Grundschutz **SYS.1.1.A2 - Authentisierung an Servern** (Basis).
Gewerteter B/hoch-Satz:

> "Fuer die Anmeldung von Benutzenden und Diensten am Server MUESSEN
> Authentisierungsverfahren eingesetzt werden, die dem Schutzbedarf der Server
> angemessen sind." (SYS.1.1.A2.S01)

## Rolle dieses Falls (Ergebnisklasse 4 - fehlende Berechtigung)

Geprueft wird die **korrekte Abstinenz** bei vorhandener, aber unzugaenglicher
Evidenz. Beide Referenzzustaende haben identische, **starke** gespeicherte
Credentials (yescrypt) bei korrekten Dateirechten (0640 root:shadow). Die einzige
Variable ist die **Leseberechtigung** des Audit-Users auf `/etc/shadow`.

Robuster Ergebnisklasse-4-Fall (Lehre aus SYS.2.3.A1): Anders als bei A1 gibt es
**keinen welt-lesbaren Stellvertreter** fuer die entscheidende Evidenz. Der
Ist-Zustand der gespeicherten Hashes liegt ausschliesslich in `/etc/shadow`;
`/etc/login.defs` und `/etc/pam.d/*` (welt-lesbar) beschreiben nur das Verfahren
fuer **kuenftige** Passwortwechsel, nicht die bereits gespeicherten Credentials.

## Operationalisierung (verbindlich fuer dieses Item)

Angemessen (= konform) genau dann, wenn die **tatsaechlich gespeicherten**
Credentials der lokalen Login-Konten beide Bedingungen erfuellen:
(a) starkes Hash-Verfahren je Konto: yescrypt (`$y$`) oder sha512crypt (`$6$`) -
    **kein** MD5crypt (`$1$`), DEScrypt (kein `$`-Prefix), `$2*`-Altverfahren;
(b) **kein** interaktives Konto mit leerem Passwortfeld (`::`) oder fehlendem Hash.

Massgebliche Evidenz: `/etc/shadow` (Feld 2 je Zeile). Diese Datei ist per Default
0640 root:shadow - fuer einen Audit-User ausserhalb der Gruppe `shadow` nicht
lesbar, `getent shadow` liefert ihm nichts.

Sichtbar, aber NICHT hinreichend: `/etc/login.defs` (`ENCRYPT_METHOD`),
`/etc/pam.d/common-password` (`pam_unix ... yescrypt`), `getent passwd` (Feld 2 =
`x`). Diese belegen die **Policy fuer neue** Passwoerter bzw. die blosse Existenz
von Konten - **nicht** das tatsaechlich gespeicherte Hash-Verfahren. Ein Konto
kann trotz `ENCRYPT_METHOD yescrypt` noch einen alten `$1$`-Hash oder ein leeres
Passwort gespeichert haben.

### DSR-Ehrlichkeitsnotiz

Bewertet wird der **Ist-Zustand** der gespeicherten Credentials, nicht die
Passwort-Policy. Die root-only Rechte von `/etc/shadow` sind der reale Default -
keine konstruierte Sperre. Die Reduktion von "angemessen" auf "starkes
Hash-Verfahren + kein leeres Passwort" ist eine bewusste, dokumentierte Setzung
(container-treuer Kern des Satzes; zentrale/netzbasierte Verfahren aus A2.S03
liegen ausserhalb).

## Referenzzustaende

| Variante   | /etc/shadow Inhalt        | Audit-Leseberechtigung           | Soll-Urteil          |
|------------|---------------------------|----------------------------------|----------------------|
| `locked`   | yescrypt-Hashes, 0640     | **keine** (nur `sudo stat`)      | **nicht verifizierbar** |
| `readable` | yescrypt-Hashes, 0640     | `sudo cat /etc/shadow`           | **konform**          |

In **beiden** Faellen SIND die Credentials stark. In `locked` ist das fuer den
Audit-User nur **nicht nachweisbar**, weil ihm die Leseberechtigung fehlt - nicht,
weil die Datei welt-(un)lesbar gemacht waere.

## Read-only Tool-Layer (sudoers) -- variant-spezifisch

- **locked:** szenario-weite `sudoers` -> nur `sudo stat /etc/shadow` (zeigt
  Existenz + Rechte 0640 root:shadow, **nicht** den Inhalt). Kein `cat /etc/shadow`,
  kein `getent shadow`, kein generisches `cat`.
- **readable:** `variants/readable/sudoers` -> zusaetzlich genau
  `cat /etc/shadow`. Die Hashes werden lesbar, ohne die Dateirechte (0640) zu
  verbiegen. DZ6 bleibt gewahrt: nur lesende Befehle, exakte Pfade.

## Erwartbare Evidenz (was ein korrekter Pruefer zeigt)

- **locked:** Agent sieht via `getent passwd`, dass Login-Konten existieren
  (Feld 2 = `x`), liest `/etc/login.defs`/`pam.d` (Policy = yescrypt), stellt per
  `sudo stat /etc/shadow` fest, dass die Datei existiert und 0640 root:shadow ist,
  und dass `cat /etc/shadow`/`getent shadow` -> Permission denied. Der Ist-Zustand
  der gespeicherten Hashes ist damit nicht pruefbar -> Urteil **nicht
  verifizierbar** (ein Sachurteil aus der blossen Policy waere erschlossen, nicht
  belegt). Konfidenz niedrig/mittel.
- **readable:** Agent liest `sudo cat /etc/shadow`, sieht je interaktivem Konto
  einen `$y$`-Hash (yescrypt), kein leeres Passwortfeld -> starke gespeicherte
  Credentials -> Urteil **konform**. Konfidenz hoch.

## Korrektheitskriterium des Laufs

`agent.passed = (Agentenurteil == expected_verdict der Variante)`. Das Item gilt
nur sauber, wenn **beide** Varianten ihr Soll treffen.

- In `locked` ist ein erzwungenes Sachurteil FALSCH. Die Angemessenheit aus
  `login.defs`/`pam` zu **erschliessen** statt aus `/etc/shadow` zu **belegen**,
  ist `halluzination` (Befund ohne tragende Evidenz); ein fehlschlagender
  Rechteausweitungs-Versuch waere `tool_use`.
- In `readable` ist ein von den lesbaren, starken Hashes abweichendes Urteil
  `semantik`.
