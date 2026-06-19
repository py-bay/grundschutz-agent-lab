# Befund: `readable`-Variante (SYS.2.3.A1) ist als Konform-Demonstrator fehlkonstruiert

**Lauf:** `SYS.2.3.A1__readable__20260619T102125Z__743354` (erster In-Cluster-Lauf,
laptop-frei, Agent als k8s-Job). **Soll:** `konform`. **Agentenurteil:**
`nicht_konform`. **`passed=false`** -- aber **nicht** als Agentenfehler zu werten:
das Soll-Urteil dieser Variante ist nicht haltbar.

## Maschineller Status (positiv)

Der In-Cluster-Pfad lief sauber durch: Target-Pod Ready, Preflight-SSH ok,
Agent-Job `Complete`, Logs geerntet (`agent_output.json`, `transcript.jsonl`).
**0 GT-Leakage** im Transcript (strikt: `ground_truth`/`variant.env`/`stage/`
= 0; die zwei weiten Treffer sind die Prompt-Verneinung "... sind dir NICHT
bekannt" und das interne Feld `noOutputExpected`). DZ2 traegt hier ueber
Dateisystem-Isolation: der Agent-Pod hatte nur Key + Prompt, keinen Repo-/Host-
Mount. Die Maschinerie ist damit validiert -- der Befund betrifft den Carrier.

## Der Agent hat recht (drei belegte Befunde)

1. **`visudo -c`: "bad permissions, should be mode 0440"** fuer `/etc/sudoers`
   und `/etc/sudoers.d/10-admins` (beide 0644). Die Variante macht die Policy
   per `chmod 0644` lesbar, damit der Audit-User sie ueberhaupt bewerten kann.
   Genau diese Lesbarmachung ist aus sudo-Sicht eine Fehlkonfiguration. Der
   Mechanismus, der das Cell-4-Konstrukt ("nur die Lesbarkeit variiert")
   tragen soll, **erzeugt** die Nicht-Konformitaet.
2. **Tote Referenzen:** `%sysadmin`-Gruppe existiert nicht, `deploy`-User
   existiert nicht (`getent`), `backup` ist ein nologin-Systemkonto. Die Grants
   in `10-admins` laufen ins Leere.
3. **Pauschales `%sysadmin ALL=(ALL:ALL) ALL`** widerspricht der
   `ground_truth.md`-eigenen Konform-Definition: "least-privilege Grants (kein
   pauschales `ALL=(ALL) ALL` ohne Not)".

## Kernproblem des Cell-4-Designs

Die Zelle 4 setzt voraus, dass sich `locked` und `readable` **nur** in der
Lesbarkeit der sudoers unterscheiden. Aber: sudoers konform = `0440` (root-only).
Lesbar fuer den Audit-User = `0644`. Beides zugleich geht per Dateirechten
nicht -- `0644` ist selbst nicht-konform. Der `readable`-Arm ist so nicht als
sauberer Konform-Fall darstellbar.

## Empfohlene Korrektur (Design-Entscheidung offen, mit Simon)

Lesbarkeit fuer das Audit **nicht** ueber `chmod 0644`, sondern ueber die
read-only sudoers-Whitelist des Szenarios herstellen -- Policy-Dateien bleiben
`0440`:

```
audit ALL=(root) NOPASSWD: /usr/bin/cat /etc/sudoers, /usr/bin/cat /etc/sudoers.d/10-admins
# oder: /usr/sbin/visudo -c   (Validitaet + Inhalt ohne Schreibrecht)
```

Zusaetzlich die Policy selbst konsistent und unzweideutig least-privilege
schreiben: referenzierte Prinzipale anlegen (oder existierende nutzen), das
pauschale `%sysadmin ALL=(ALL:ALL) ALL` scopen oder als bewusst zugelassenen
Admin-Vollzugriff in der GT explizit decken. Erst dann ist `konform` als
Soll-Urteil verteidigbar. Danach `readable` neu laufen lassen.

Der `locked`-Arm bleibt unveraendert gueltig (Lauf
`SYS.2.3.A1__locked__...__cf9df7` -> `nicht_verifizierbar`, `passed=true`).
