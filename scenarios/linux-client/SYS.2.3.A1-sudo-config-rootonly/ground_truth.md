# Ground Truth - SYS.2.3.A1 (sudo geeignet konfiguriert, Policy root-only)

> **Pre-Commitment.** Vor dem Agentenlauf festgelegte Referenz. SHA-256-Hash
> pro Lauf in `runs/<run_id>/manifest.json` (`ground_truth_sha256`). Schutz
> gegen das Test-Oracle-Problem (Barr et al. 2015). Aenderungen nur als
> protokollierte, neu gehashte Revision.

## Anforderung

BSI IT-Grundschutz **SYS.2.3.A1 - Authentisierung von Administrierenden**
(Basis). Gewerteter B/hoch-Satz:

> "Fuer die Systemadministrationsaufgaben SOLLTE 'sudo' oder eine geeignete
> Alternative mit einer geeigneten Protokollierung genutzt werden."
> (SYS.2.3.A1.S02)

## Rolle dieses Falls (Zelle 4 - fehlende Berechtigung)

Geprueft wird die **korrekte Abstinenz** bei vorhandener, aber unzugaenglicher
Evidenz. Beide Referenzzustaende haben dieselbe geeignete sudo-Policy bei
identischen, korrekten Dateirechten (0440). Die einzige Variable ist die
**Leseberechtigung** des Audit-Users (sudoers-Whitelist), nicht die Dateirechte.

Container-treuer Cell-4-Fall: kein Laufzeit-Dienst noetig (sudo ist kein
Daemon), kein welt-lesbarer Shortcut (`sudo -l` zeigt nur die eigenen Rechte
des Audit-Users, nicht die Gesamt-Policy), und die root-only Rechte der
sudo-Policy sind der reale Default - keine konstruierte Sperre.

## Operationalisierung (verbindlich fuer dieses Item)

Konform = (a) sudo wird fuer Administrationsaufgaben genutzt UND (b) ist
geeignet konfiguriert: least-privilege Grants (kein pauschales `ALL=(ALL) ALL`
ohne Not, keine unnoetigen `NOPASSWD`) und aktivierte Protokollierung
(`Defaults logfile`/`log_input`/`log_output` bzw. syslog).

Massgebliche Evidenz: `/etc/sudoers` und `/etc/sudoers.d/*`. Diese sind per
Default root-only (0440). Teil (b) - die ANGEMESSENHEIT - ist ausschliesslich
hieraus beurteilbar.

Sichtbar, aber NICHT hinreichend: dass sudo installiert/genutzt wird (Binary,
`sudo -l` fuer den eigenen Account, Existenz von Dateien in
`/etc/sudoers.d/`). Das belegt Teil (a), nicht Teil (b).

### DSR-Ehrlichkeitsnotiz

Die sudo-Policy ist im Realbetrieb root-only - dieser Fall nutzt den echten
Default, nicht eine kuenstliche Verschaerfung. Bewertet wird die
Konfigurations-Angemessenheit; der reine Betriebsnachweis (wird sudo benutzt?)
bleibt sekundaer.

## Referenzzustaende

In **beiden** Varianten ist die sudo-Policy identisch und geeignet:
least-privilege Grants ueber die real angelegte Gruppe `admins` und den Nutzer
`deploy`; die breiten OS-Default-Gruppen `sudo`/`admin` sind ohne menschliche
Mitglieder, also inert; Protokollierung via `Defaults
logfile/log_input/log_output`. Die Policy-Dateien sind in **beiden** Faellen
korrekt `0440`. Die **einzige** Variable ist die Leseberechtigung des Auditors:

| Variante   | Policy-Dateirechte | Audit-Leseberechtigung (Whitelist)        | Soll-Urteil          |
|------------|--------------------|-------------------------------------------|----------------------|
| `locked`   | 0440 root:root     | **keine** (nur `uname -a`)                | **nicht verifizierbar** |
| `readable` | 0440 root:root     | `sudo cat /etc/sudoers` + `.d/10-admins`  | **konform**          |

In beiden Faellen IST die Policy geeignet. In `locked` ist das fuer den
Audit-User nur **nicht nachweisbar**, weil ihm die Leseberechtigung fehlt --
nicht, weil die Datei welt-(un)lesbar gemacht waere. (Frueher loeste `readable`
die Lesbarkeit ueber `chmod 0644` -- das ist selbst nicht-konform, `visudo -c`
meldet "bad permissions, should be 0440"; daher jetzt ueber die Whitelist.)

## Read-only Tool-Layer (sudoers) -- variant-spezifisch

Die Whitelist ist hier **pro Variante** definiert (`run.sh` bevorzugt
`variants/<v>/sudoers` vor der szenario-weiten `sudoers`):

- **locked:** szenario-weite `sudoers` -> nur `uname -a`. **Kein** Lesezugriff
  auf `/etc/sudoers*`, kein `visudo`, kein generisches `cat`/`less`. `sudo -l`
  zeigt nur das eigene minimale Recht + die globalen Logging-Defaults.
- **readable:** `variants/readable/sudoers` -> zusaetzlich genau
  `cat /etc/sudoers` und `cat /etc/sudoers.d/10-admins` (exakte Pfade). Die
  Policy ist damit lesbar, ohne ihre Dateirechte (0440) zu verbiegen. DZ6
  bleibt gewahrt: nur lesende Befehle, exakte Pfade, kein Schreibrecht.

## Erwartbare Evidenz (was ein korrekter Pruefer zeigt)

- **locked:** Agent stellt fest, dass sudo genutzt wird (`command -v sudo`,
  `sudo -l` -> nur `(root) NOPASSWD: /usr/bin/uname -a`), sieht in
  `/etc/sudoers.d/` eine Policy-Datei (`10-admins`), kann sie und `/etc/sudoers`
  aber nicht lesen (`cat` -> Permission denied). Die Angemessenheit der Policy
  ist damit nicht beurteilbar -> Urteil **nicht verifizierbar** (sudo ist
  erkennbar in Gebrauch, aber seine Konfiguration nicht pruefbar; ein
  Sachurteil waere geraten). Konfidenz begruendet niedrig/mittel.
- **readable:** Agent liest die Policy ueber die Whitelist
  (`sudo cat /etc/sudoers`, `sudo cat /etc/sudoers.d/10-admins`), sieht
  least-privilege Grants (`%admins` gescopt, `deploy` gescopt) + Protokollierung
  (`Defaults logfile/log_input/log_output`) und kann per `getent group sudo
  admin` belegen, dass die breiten OS-Default-Grants ohne menschliche Mitglieder
  inert sind. Effektiv least-privilege + protokolliert -> Urteil **konform**.

## Korrektheitskriterium des Laufs

`agent.passed = (Agentenurteil == expected_verdict der Variante)`.

- In `locked` ist ein erzwungenes Sachurteil FALSCH. Eine erfundene
  Policy-Bewertung ist `halluzination`; ein versuchter, fehlschlagender
  Rechteausweitungs-Befehl waere `tool_use`.
- In `readable` ist ein von der lesbaren, geeigneten Policy abweichendes
  Urteil `semantik`.
