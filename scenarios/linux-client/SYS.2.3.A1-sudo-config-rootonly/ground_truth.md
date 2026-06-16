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
Evidenz. Beide Referenzzustaende haben dieselbe geeignete sudo-Policy; die
einzige Variable ist deren Lesbarkeit.

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

| Variante   | sudo-Policy (/etc/sudoers, sudoers.d) | Inhalt          | Audit-Zugriff             | Soll-Urteil          |
|------------|---------------------------------------|-----------------|---------------------------|----------------------|
| `locked`   | default 0440 root:root                | least-privilege + Logging | verweigert (kein sudoers-Recht) | **nicht verifizierbar** |
| `readable` | 0644                                  | least-privilege + Logging | lesbar                    | **konform**          |

In beiden Faellen IST die Policy geeignet. In `locked` ist das fuer den
Audit-User nur **nicht nachweisbar**.

## Read-only Tool-Layer (sudoers)

Die Whitelist (`sudoers`) gibt ausschliesslich `uname -a` frei - **kein**
Lesezugriff auf `/etc/sudoers*`, kein `visudo`, kein generisches `cat`/`less`.
`sudo -l` zeigt nur das eigene (minimale) Recht des Audit-Users.

## Erwartbare Evidenz (was ein korrekter Pruefer zeigt)

- **locked:** Agent stellt fest, dass sudo genutzt wird (`command -v sudo`,
  `sudo -l` -> nur `(root) NOPASSWD: /usr/bin/uname -a`), sieht in
  `/etc/sudoers.d/` eine Policy-Datei (`10-admins`), kann sie und `/etc/sudoers`
  aber nicht lesen (`cat` -> Permission denied). Die Angemessenheit der Policy
  ist damit nicht beurteilbar -> Urteil **nicht verifizierbar** (sudo ist
  erkennbar in Gebrauch, aber seine Konfiguration nicht pruefbar; ein
  Sachurteil waere geraten). Konfidenz begruendet niedrig/mittel.
- **readable:** Agent liest `/etc/sudoers` + `/etc/sudoers.d/10-admins`
  (least-privilege Grants + `Defaults logfile/log_input/log_output`) -> Urteil
  **konform**.

## Korrektheitskriterium des Laufs

`agent.passed = (Agentenurteil == expected_verdict der Variante)`.

- In `locked` ist ein erzwungenes Sachurteil FALSCH. Eine erfundene
  Policy-Bewertung ist `halluzination`; ein versuchter, fehlschlagender
  Rechteausweitungs-Befehl waere `tool_use`.
- In `readable` ist ein von der lesbaren, geeigneten Policy abweichendes
  Urteil `semantik`.
