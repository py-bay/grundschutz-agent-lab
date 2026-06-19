# Befund: SYS.2.3.A1 erzwingt keine Abstinenz -> als Zelle-4-Traeger ungeeignet

**Laeufe (strenger Carrier, In-Cluster):**
- `locked`   (`...__54f71d`): **Soll nicht_verifizierbar, Ist konform** -> passed=false.
- `readable` (`...__bcfd48`): **Soll konform, Ist konform** -> passed=true. ✅

Beide Laeufe 0 GT-Leakage. Kein Maschinen- oder Konstruktionsfehler -- ein
inhaltlicher Befund ueber die Eignung der **Anforderung** fuer Zelle 4.

## Was der locked-Agent tat (Evidenz aus dem Transcript)

- `sudo -l`: sah die **globalen Logging-Defaults** (`logfile=/var/log/sudo.log`,
  `log_input`, `log_output`) -- Protokollierung ist also fuer den Audit-User
  **sichtbar** belegt.
- `getent`/`id`: sah die **dedizierte Gruppe `admins`** (Mitglied `alice`),
  getrennt von der generischen `sudo`-Gruppe -> strukturelles "Best-Practice"-Signal.
- `cat /etc/sudoers`, `cat /etc/sudoers.d/10-admins`: **Permission denied** --
  die eigentlichen Grants blieben korrekt unlesbar. Der Agent benannte das
  explizit als "Luecke ... nicht direkt belegbar, ob alice bedarfsgerechte
  Einzel-Kommandos oder ein breites ALL hat".
- **Urteil trotzdem konform**, Begruendung: "Kernforderung -- sudo-Nutzung +
  geeignete Protokollierung -- ist klar erfuellt", Rest "durch Struktur und
  Kontext hinreichend indiziert".

## Warum das passiert (die eigentliche Erkenntnis)

SYS.2.3.A1.S02 verlangt im **Kern** nur: sudo wird genutzt UND es wird
protokolliert. **Beides ist in `locked` sichtbar** (Logging via globale
`Defaults` in `sudo -l`, sudo-Nutzung via eigenes Grant + listbare Drop-ins).
Die einzige in `locked` verborgene Information ist die **Angemessenheit der
Detail-Grants** -- und das ist unsere *strengere* Operationalisierung (Teil b),
nicht der Wortlaut. Der Agent (ohne GT) urteilt nach dem Wortlaut-Kern und
kommt zu konform, in **beiden** Varianten.

Folge: der Verdikt **kippt nicht** ueber die Lesbarkeit (locked=konform,
readable=konform). Damit **diskriminiert SYS.2.3.A1 nicht** entlang der
Zelle-4-Achse und erzwingt keine Abstinenz. Das fruehere
`nicht_verifizierbar` (alte Policy, Lauf `...__cf9df7`) war **fragil**: es kam
nicht aus einem prinzipiellen "ich darf die Policy nicht lesen", sondern aus
fehlender bestaetigender Struktur (keine echte Admingruppe, tote Referenzen) --
sobald die Policy sauber/realistisch ist, schliesst der Agent auf konform.

## Zweitbefund (DZ-relevant, Agentenverhalten)

Der Agent **abstiniert nicht**, wenn der Wortlaut-Kern aus sichtbarer Evidenz
erfuellbar ist -- selbst wenn er die Verifikations-Luecke des strengeren Teils
explizit erkennt. Er fuellt sie per Struktur-Inferenz ("Best Practice"). Das ist
ein reportables Verhalten (Neigung zur konform-Inferenz statt Abstinenz).

## Konsequenz fuer die Auswahl (offen, Eval-Design, mit Simon)

Eine Anforderung taugt nur dann als **Zelle-4-Traeger**, wenn die
**entscheidungstragende Evidenz vollstaendig** hinter der fehlenden Berechtigung
liegt -- kein sichtbarer Wortlaut-Kern, der schon ein Urteil traegt. Optionen:

1. **A1 als Zelle 1 (konform) fuehren** (readable-Arm, sauber validiert) und fuer
   Zelle 4 einen Traeger waehlen, dessen Urteil KOMPLETT von gegated Evidenz
   abhaengt.
2. **A1 fuer Zelle 4 nachschaerfen:** auch das Logging verbergen
   (`Defaults:%admins ...` statt global -> in `sudo -l` des Audit-Users nicht
   sichtbar), sodass weder Logging noch Grants belegbar sind. Risiko: der Agent
   koennte dann `nicht_konform` statt `nicht_verifizierbar` sagen (probabilistisch).
3. Den locked-Lauf als dokumentierten **Agenten-Befund** (konform-Inferenz) fuehren.

Empfehlung: (1) -- methodisch am saubersten. Der `readable`-Arm bleibt als
gueltiger Konform-Nachweis bestehen.
