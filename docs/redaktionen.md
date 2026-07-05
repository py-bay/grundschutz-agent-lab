# Redaktionen für die öffentliche Archivierung

Vor der Veröffentlichung als öffentliches Archiv wurde die Git-Historie dieses
Repositories **einmalig, minimal und deterministisch** redigiert. Dieser Vermerk
dokumentiert vollständig, was geändert wurde und warum — damit der Verbatim-
Anspruch der Lauf-Transkripte nachvollziehbar bleibt.

## Was redigiert wurde

Zwei Klassen von Wegwerf-Lab-Artefakten, beide aus dem Szenario
`SYS.1.1.A2-shadow-hash-rootonly` (EK4, `/etc/shadow`-Lesbarkeit):

| Ursprünglicher Wert | Ersetzt durch | Wo |
|---|---|---|
| Klartext-Passphrase des `svcadmin`-Wegwerfkontos (`chpasswd`-Zeile) | `REDACTED-LAB-PASSPHRASE` | `variants/{locked,readable}/setup.sh` (2 Dateien) |
| Der daraus resultierende yescrypt-Hash (`$y$j9T$…`) aus `/etc/shadow` | `REDACTED-YESCRYPT-HASH` | `runs/*/transcript.jsonl` + `runs/*/agent_output.json` (20 Lauf-Artefakte) |

Insgesamt 22 Dateien über alle Commits hinweg (Rewrite via `git filter-branch`,
crypt-Base64-präzise Substitution `\$y\$[./A-Za-z0-9]+\$[./A-Za-z0-9]+\$[./A-Za-z0-9]+`).

## Warum das kein Sicherheitsvorfall war (und die Redaktion rein kosmetisch)

Der `svcadmin`-Hash war der yescrypt-Hash einer Passphrase, die ohnehin im
Klartext im selben Repo stand, für ein Konto auf einem **längst zerstörten,
ephemeren Pod**. Kryptografisch wertlos. Es wurden nie echte Credentials,
Tokens oder Schlüssel committet (SSH-Keys liegen unter `runs/*/ssh/` und sind
per `.gitignore` ausgeschlossen; OAuth-/OTel-Secrets leben nur in
k8s-Secrets). Die Redaktion dient der sauberen Optik eines öffentlichen
Archivs, nicht der Gefahrenabwehr.

## Integritäts-Auswirkung (ehrlich ausgewiesen)

- **Ground Truth unberührt:** keine `ground_truth.md` wurde verändert;
  `ground_truth_sha256` verifiziert unverändert. Ebenso `prompt_sha256` und
  `sudoers_sha256`.
- **`state_sha256` der A2-shadow-Läufe:** Da die redigierte `setup.sh` Teil des
  je Lauf gehashten Stage-Verzeichnisses war, lässt sich `state_sha256` dieser
  Läufe **nicht** mehr aus der (redigierten) `setup.sh` reproduzieren; der im
  Manifest festgehaltene Wert spiegelt die ursprünglichen, unredigierten
  Stage-Bytes. Betroffen ist ausschließlich `SYS.1.1.A2-shadow-hash-rootonly`.
- **Modell-Urteile, Evidenz, Begründungen, Telemetrie:** byte-identisch
  erhalten. Es wurde bewiesen, dass der Rewrite exakt der Token-Substitution
  entspricht und keinerlei Fließtext verändert hat.

## Nicht redigiert (bewusst)

Interne Cluster-Bezeichner (`*.svc.cluster.local`, Namespace `grundschutz-lab`,
Registry-/OTel-Hostnamen unter `pybay.de`) bleiben in den Transkripten stehen:
von außen nicht erreichbar, und das README weist das Cluster-Substrat ohnehin
als nicht-Teil-der-Veröffentlichung aus.
