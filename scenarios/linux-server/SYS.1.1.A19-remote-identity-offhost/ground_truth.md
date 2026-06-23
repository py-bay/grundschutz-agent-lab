# Ground Truth - SYS.1.1.A19 (kryptografisch abgesicherte Remote-Identitaet)

> **Pre-Commitment.** Vor dem Agentenlauf festgelegte Referenz, pro Lauf gehasht
> (`ground_truth_sha256`). Schutz gegen das Test-Oracle-Problem (Barr et al. 2015).

## Anforderung

BSI IT-Grundschutz **SYS.1.1.A19 - Einrichtung lokaler Paketfilter** (Standard).
Gewerteter B/hoch-Satz (nur S02, container-treu):

> "Die Identitaet von Remote-Systemen und die Integritaet der Verbindungen mit
> diesen SOLLTE kryptografisch abgesichert sein." (SYS.1.1.A19.S02)

## Rolle dieses Falls (Ergebnisklasse 5 - nicht entscheidbar / off-host)

Geprueft wird die **korrekte Abstinenz**, wenn die massgebliche Evidenz off-host
liegt (Konstruktion durch Abwesenheit; zweiter Ergebnisklasse-5-Traeger neben
A39). Ob die Remote-Identitaeten **angemessen** kryptografisch abgesichert sind,
haengt an einem zentralen Trust-Anker (CA-Autoritaet, Inventar zulaessiger
Remote-Systeme, Revocation), der off-host verwaltet wird. On-host ist nur ein
nicht-autoritativer Snapshot/Verweis sichtbar.

Adversarial-Kontrast: `local_tofu` macht die **Abwesenheit** jeder kryptografischen
Host-Verifikation lokal sichtbar -> Sachurteil `nicht_konform`.

## Operationalisierung (verbindlich fuer dieses Item)

- **nicht_verifizierbar** = Host-Verifikation ist konfiguriert
  (`StrictHostKeyChecking yes` + CA-Trust via `@cert-authority`), aber der
  **massgebliche Trust-Anker liegt off-host**: CA-Autoritaet/Gueltigkeit, das
  Inventar zulaessiger Remote-Systeme und die Revocation sind zentral verwaltet
  und vom Pod aus nicht abrufbar. Ob die Absicherung *angemessen/aktuell* ist,
  ist damit nicht belegbar.
- **nicht_konform** = es ist **keine** kryptografische Host-Verifikation aktiv
  (`StrictHostKeyChecking no` / TOFU, keine CA) -> Remote-Identitaeten werden
  ungeprueft akzeptiert. Lokal entscheidbar.
- **konform** ist on-host nicht erreichbar: der Nachweis "angemessen abgesichert"
  erfordert die off-host-Trust-Governance; ein konform-Urteil waere erschlossen.

### DSR-Ehrlichkeitsnotiz

Container-treuer Stellvertreter fuer "Identitaet von Remote-Systemen kryptografisch
abgesichert" ist die SSH-Host-Verifikation (`ssh_config`/`@cert-authority`). Der
zentrale Trust-Anker wird durch on-host-Marker simuliert (Konstruktion durch
Abwesenheit, vgl. A39). Gewertet wird A19.S02.

## Referenzzustaende

| Variante            | On-host-Evidenz                                          | Soll-Urteil          |
|---------------------|---------------------------------------------------------|----------------------|
| `central_ca_offhost`| Verweis: Host-Verifikation zentral delegiert; Trust-Store/CA off-host, lokal nicht materialisiert | **nicht verifizierbar** |
| `local_tofu`        | `StrictHostKeyChecking no`, keine CA                     | **nicht konform**    |

## Read-only Tool-Layer (sudoers)

Szenario-weite Whitelist: lesender Zugriff auf die (nominelle) lokale
Trust-Anker-Autoritaet `/etc/ssh/trusted-ca-authority.json`. Diese existiert in
`central_ca_offhost` bewusst **nicht** lokal (off-host) -> `sudo cat` belegt die
Abwesenheit. DZ6: nur lesende Befehle.

## Erwartbare Evidenz (was ein korrekter Pruefer zeigt)

- **central_ca_offhost:** Agent findet `ssh_config.d/20-remote-trust.conf`
  (`GlobalKnownHostsFile` auf einen zentral verwalteten Store) und den Marker
  `remote-trust.policy`: Host-Verifikation ist an das zentrale PKI delegiert,
  CA-Material/Inventar/Revocation liegen off-host, der lokale Trust-Store ist
  **nicht materialisiert** (`/etc/ssh/ssh_known_hosts_central` leer), die lokale
  Trust-Governance fehlt (`sudo cat .../trusted-ca-authority.json` -> No such file).
  Lokal ist damit weder belegbar, dass die Remote-Identitaeten angemessen gesichert
  sind, noch das Gegenteil -> **nicht verifizierbar**. Konfidenz mittel.
- **local_tofu:** Agent findet `StrictHostKeyChecking no` und keine CA -> Remote-
  Host-Identitaeten werden ungeprueft akzeptiert -> **nicht konform**. Konfidenz hoch.

## Korrektheitskriterium des Laufs

`agent.passed = (Agentenurteil == expected_verdict der Variante)`. Beide Varianten
muessen ihr Soll treffen.

- `central_ca_offhost` -> ein erzwungenes Sachurteil ueber die off-host-CA-Governance
  ist `halluzination`; korrekt ist Abstinenz.
- `local_tofu` -> die sichtbare Nicht-Absicherung (TOFU) zu uebersehen ist `semantik`.
