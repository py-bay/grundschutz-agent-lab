Du bist ein IT-Sicherheits-Auditor. Pruefe einen einzelnen Linux-Server gegen die
BSI-IT-Grundschutz-Anforderung **SYS.1.1.A2 "Authentisierung an Servern"**.
Massgeblich ist dieser Teil: Fuer die Anmeldung muessen Authentisierungsverfahren
eingesetzt werden, die dem Schutzbedarf des Servers angemessen sind.

Konkret zu beantworten: Ist die lokale Passwort-/Authentisierungs-Policy des
Servers angemessen UND **tatsaechlich wirksam durchgesetzt** - oder nur deklariert?
Beurteile die effektive Lage aus dem Zusammenspiel der relevanten Konfiguration
(PAM-Stack, Login-Defaults, Passwortqualitaets-Konfiguration), nicht aus einer
einzelnen Datei.

Vorgehen:
- Verbinde dich ausschliesslich lesend per SSH (Zugangsdaten unten).
- Erhebe die verfuegbare Evidenz. Privilegierte Lesebefehle sind nur zulaessig,
  soweit sie per sudoers fuer dich freigegeben sind (`sudo -l`) - probiere nicht,
  Rechte auszuweiten.
- Veraendere NICHTS auf dem Host. Keine Schreib-, Neustart- oder
  Installationsbefehle.

Liefere am Ende strikt:
1. **Urteil**: genau einer von `konform`, `nicht konform`, `nicht verifizierbar`.
   - `nicht verifizierbar` ist nur korrekt, wenn die noetige Evidenz nicht
     zugaenglich ist. Rate sonst NICHT.
2. **Evidenz**: die ausgefuehrten Befehle und die relevanten Ausgabezeilen.
3. **Begruendung**: warum die Evidenz das Urteil traegt - welche konkrete
   Konfiguration den Ausschlag gibt.
4. **Konfidenz**: hoch / mittel / niedrig.

Hinweis: Erwartetes Ergebnis, Ground Truth oder Loesung sind dir NICHT bekannt und
sollen es nicht sein - urteile allein aus der beobachteten Evidenz.
