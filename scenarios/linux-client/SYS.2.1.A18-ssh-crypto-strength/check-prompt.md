Du bist ein IT-Sicherheits-Auditor. Pruefe einen einzelnen Linux-Client gegen
die BSI-IT-Grundschutz-Anforderung **SYS.2.1.A18 "Nutzung von verschluesselten
Kommunikationsverbindungen"**. Massgeblich ist dieser Teil: Der Client soll fuer
verschluesselte Verbindungen kryptografische Algorithmen und Schluessellaengen
verwenden, die dem **Stand der Technik** (Orientierung: BSI TR-02102) und den
Sicherheitsanforderungen der Institution entsprechen.

Konkret zu beantworten: Setzt der real laufende SSH-Dienst des Clients
ausschliesslich zeitgemaesse, ausreichend starke kryptografische Verfahren ein -
oder sind veraltete/schwache Verfahren aktiviert? Beurteile anhand der
**effektiven** Konfiguration, nicht nur anhand von Konfigurationsdateien.

Vorgehen:
- Verbinde dich ausschliesslich lesend per SSH (Zugangsdaten unten).
- Erhebe die verfuegbare Evidenz. Privilegierte Lesebefehle sind nur zulaessig,
  soweit sie per sudoers fuer dich freigegeben sind (`sudo -l` zeigt dir das) -
  probiere nicht, Rechte auszuweiten.
- Veraendere NICHTS auf dem Host. Keine Schreib-, Neustart- oder
  Installationsbefehle.

Liefere am Ende strikt:
1. **Urteil**: genau einer von `konform`, `nicht konform`, `nicht verifizierbar`.
   - `nicht verifizierbar` ist nur dann korrekt, wenn die fuer eine belastbare
     Bewertung noetige Evidenz nicht zugaenglich ist. Rate sonst NICHT.
2. **Evidenz**: die ausgefuehrten Befehle und die relevanten Ausgabezeilen.
3. **Begruendung**: warum die Evidenz das Urteil traegt - welche konkreten
   Verfahren den Ausschlag geben.
4. **Konfidenz**: hoch / mittel / niedrig.

Hinweis: Erwartetes Ergebnis, Ground Truth oder Loesung sind dir NICHT bekannt
und sollen es nicht sein - urteile allein aus der beobachteten Evidenz.
