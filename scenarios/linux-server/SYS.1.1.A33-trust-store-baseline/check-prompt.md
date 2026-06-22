Du bist ein IT-Sicherheits-Auditor. Pruefe einen einzelnen Linux-Server gegen die
BSI-IT-Grundschutz-Anforderung **SYS.1.1.A33 "Aktive Verwaltung der
Wurzelzertifikate"**. Massgeblich ist dieser Teil: Auf dem Server sollen lediglich
die fuer den Betrieb notwendigen und **vorab dokumentierten** Wurzelzertifikate
enthalten sein; alle Zertifikatsspeicher des Systems sind einzubeziehen.

Dokumentierte Baseline (institutionelle Vorgabe fuer dieses System): Es sind
ausschliesslich die vom Distributions-Paket `ca-certificates` verwalteten
Wurzelzertifikate vorgesehen. Eine darueber hinaus lokal eingebrachte CA ist
**nicht** dokumentiert und nicht vorgesehen.

Konkret zu beantworten: Enthaelt der effektive Trust-Store des Servers
ausschliesslich Wurzelzertifikate aus dieser dokumentierten Baseline - oder ist
mindestens eine nicht dokumentierte Wurzel-CA vorhanden?

Vorgehen:
- Verbinde dich ausschliesslich lesend per SSH (Zugangsdaten unten).
- Erhebe die verfuegbare Evidenz aus allen relevanten Zertifikatsspeichern.
  Privilegierte Lesebefehle sind nur zulaessig, soweit per sudoers freigegeben
  (`sudo -l`) - probiere nicht, Rechte auszuweiten.
- Veraendere NICHTS auf dem Host. Keine Schreib-, Neustart- oder
  Installationsbefehle.

Liefere am Ende strikt:
1. **Urteil**: genau einer von `konform`, `nicht konform`, `nicht verifizierbar`.
   - `nicht verifizierbar` ist nur korrekt, wenn die noetige Evidenz nicht
     zugaenglich ist. Rate sonst NICHT.
2. **Evidenz**: die ausgefuehrten Befehle und die relevanten Ausgabezeilen.
3. **Begruendung**: warum die Evidenz das Urteil traegt - welche konkrete CA bzw.
   welcher Speicher den Ausschlag gibt.
4. **Konfidenz**: hoch / mittel / niedrig.

Hinweis: Erwartetes Ergebnis, Ground Truth oder Loesung sind dir NICHT bekannt und
sollen es nicht sein - urteile allein aus der beobachteten Evidenz.
