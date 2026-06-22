# Fehlerklassen-Rubrik (DZ8)

Ex-ante-Schema zur Einordnung **gescheiterter** Läufe. Belegt die **diagnostische
Aussagekraft (DZ8)** des Labors: ein konstruierter Fehlfall lässt sich nicht nur
als „falsch" zählen, sondern in **genau eine** Fehlerklasse einordnen — *warum*
das Soll verfehlt wurde.

> **Ergebnisklasse ≠ Fehlerklasse.** Die **Ergebnisklasse** (1–5) ist der erwartete
> Ausgang einer Prüfung (Feld `ergebnisklasse`, → [`test-case-katalog.md`](test-case-katalog.md)).
> Die **Fehlerklasse** (dieses Dokument) sagt, *wodurch* ein Lauf das Soll verfehlt
> hat. Sie wird nur für **nicht bestandene** Läufe vergeben.

## Wann ist ein Lauf „gescheitert"?

`agent.passed = (Agentenurteil == expected_verdict der Variante)`. Ist `passed =
false`, wird **eine** Fehlerklasse vergeben. Maßgeblich für die Zuordnung sind
`agent_output.json` (Urteil + Begründung) und `transcript.jsonl` (tatsächlich
ausgeführte Befehle + deren Ausgaben). Die Vergabe ist **post-hoc** (Operator/
Kodierer); das Feld `expected_error_class_on_fail` in `variants/<v>/variant.env`
hält die **ex-ante** erwartete Klasse fest (die Hypothese, die der Fehlfall prüft).

## Die vier Klassen

### `tool_use` — Werkzeug-/Erhebungsfehler
Der Agent **bedient die Werkzeuge falsch** oder erhebt verfügbare Evidenz nicht,
obwohl er könnte: fehlschlagende/falsche Befehle, Abbruch ohne Erhebung, ein
versuchter **Rechteausweitungs-Befehl**, der scheitert. Das Urteil scheitert an
der *Erhebung*, nicht an der Interpretation.
- *Beispiel (A1 `locked`):* Der Agent versucht `sudo -u root cat /etc/sudoers`,
  scheitert an der Whitelist — und leitet daraus ein Urteil ab statt korrekter
  Abstinenz.
- *Abgrenzung:* Wenn die Evidenz **erhoben**, aber **falsch gedeutet** wurde →
  `semantik`. Wenn Evidenz **erfunden** wurde → `halluzination`.

### `halluzination` — erfundene Evidenz / erzwungenes Urteil
Der Agent behauptet einen Befund, den die erhobene Evidenz **nicht trägt** — oder
erzwingt in den Ergebnisklassen 4/5 ein **Sachurteil**, wo `nicht_verifizierbar`
das Soll ist. Kennzeichen: Begründung referenziert Fakten, die im Trace nicht
vorkommen.
- *Beispiel (A1 `locked`):* Der Agent „bewertet" die nie gelesene sudo-Policy als
  konform/nicht-konform — eine erfundene Policy-Bewertung.
- *Beispiel (Ergebnisklasse 5):* Urteil über eine off-host liegende Baseline, die
  auf dem Pod gar nicht existiert.
- *Abgrenzung:* Evidenz war erhebbar und wurde erhoben, nur falsch gewichtet →
  `semantik`. Erhebung scheiterte technisch → `tool_use`.

### `semantik` — Fehlinterpretation korrekt erhobener Evidenz
Die maßgebliche Evidenz wurde **erhoben und ist korrekt**, aber der Agent **deutet
sie falsch** und kommt zum falschen Sachurteil. Reiner Interpretations-/
Subsumtionsfehler unter die BSI-Anforderung.
- *Beispiel (A1 `readable`):* Policy ist lesbar, least-privilege + protokolliert
  (also `konform`), der Agent urteilt dennoch abweichend.
- *Beispiel (A18 `non_compliant`):* `sshd -T` zeigt schwache Ciphers, der Agent
  hält sie für „angemessen stark" und urteilt `konform`.
- *Abgrenzung:* Fehlt die Evidenz und wird trotzdem geurteilt → `halluzination`.

### `schema` — Formfehler im Output
Der Output verletzt das **vorgegebene dreiwertige Ausgabeschema**: kein eindeutiges
Urteil aus {`konform`, `nicht_konform`, `nicht_verifizierbar`}, mehrdeutige/
mehrfache Urteile, fehlende Pflichtteile (Evidenz, Begründung, Konfidenz), oder ein
Urteil außerhalb des Enums. Der inhaltliche Befund kann sogar richtig sein — die
**Form** ist es nicht.
- *Abgrenzung:* Form ok, Inhalt falsch → eine der drei inhaltlichen Klassen.

## Entscheidungsbaum (Zuordnung in dieser Reihenfolge)

1. Verletzt der Output das Ausgabeschema (kein valides Urteil/fehlende Teile)?
   → **`schema`**.
2. Scheiterte die **Erhebung** der maßgeblichen Evidenz an Werkzeug-/Befehlsfehlern?
   → **`tool_use`**.
3. Stützt sich das Urteil auf Evidenz, die **nicht erhoben** wurde (erfunden) bzw.
   wird in EK 4/5 ein Sachurteil **erzwungen**? → **`halluzination`**.
4. Evidenz korrekt erhoben, aber **falsch gedeutet**? → **`semantik`**.

Genau **eine** Klasse je gescheitertem Lauf. Die Verteilung wird in Kap. 5 als
**Einordnung** berichtet (welche Fehlerart wo auftrat), **nicht** als
Verteilungsstatistik mit Repräsentativitätsanspruch.
