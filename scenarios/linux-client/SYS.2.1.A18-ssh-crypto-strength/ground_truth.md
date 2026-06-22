# Ground Truth - SYS.2.1.A18 (verschluesselte Kommunikation, SSH-Krypto)

> **Pre-Commitment.** Vor dem Agentenlauf festgelegte Referenz. SHA-256-Hash pro
> Lauf in `runs/<run_id>/manifest.json` (`ground_truth_sha256`). Schutz gegen das
> Test-Oracle-Problem (Barr et al. 2015). Aenderungen nur als protokollierte, neu
> gehashte Revision.

## Anforderung

BSI IT-Grundschutz **SYS.2.1.A18 - Nutzung von verschluesselten
Kommunikationsverbindungen** (Standard). Gewerteter B/hoch-Satz:

> "Die Clients SOLLTEN kryptografische Algorithmen und Schluessellaengen
> verwenden, die dem Stand der Technik und den Sicherheitsanforderungen der
> Institution entsprechen." (SYS.2.1.A18.S02)

## Rolle dieses Falls (Ergebnisklassen 1 + 2 - Sachurteil-Paar)

Geprueft wird die **Diskriminierung** (DZ4) am selben Traeger: identische
Maschinerie, gegensaetzliches Soll. `compliant` ist der saubere Konform-Fall
(Ergebnisklasse 1), `non_compliant` der saubere Verstoss (Ergebnisklasse 2). Ein
konstant urteilender Agent faellt am Kontrast zwingend auf. Die maessgebliche
Evidenz ist hier **vollstaendig und lesbar** erhebbar - Abstinenz
(`nicht_verifizierbar`) ist in beiden Varianten falsch.

## Operationalisierung (verbindlich fuer dieses Item)

Massgebliche Evidenz: die **effektive** SSH-Server-Konfiguration via
`sudo /usr/sbin/sshd -T`, Felder `ciphers`, `macs`, `kexalgorithms`.

- **Konform** = alle drei Suiten enthalten ausschliesslich Verfahren nach Stand
  der Technik (BSI TR-02102-4 fuer SSH): AEAD-/CTR-Ciphers (z.B.
  `aes256-gcm@openssh.com`, `chacha20-poly1305@openssh.com`, `aes*-ctr`),
  SHA2-MACs (bevorzugt ETM, z.B. `hmac-sha2-512-etm@openssh.com`), moderne KEX
  (`curve25519-sha256`, `diffie-hellman-group16/18-sha512`).
- **Nicht konform** = mindestens ein **veraltetes/schwaches** Verfahren ist
  aktiviert: CBC-Ciphers (`*-cbc`, `3des-cbc`), SHA1-MACs (`hmac-sha1*`),
  MD5-MACs (`hmac-md5*`), SHA1-basierte oder Legacy-DH-KEX
  (`diffie-hellman-group1-sha1`, `diffie-hellman-group14-sha1`,
  `*-group-exchange-sha1`).

Dass moderne Verfahren **zusaetzlich** angeboten werden, heilt aktivierte
Schwachverfahren **nicht** (ein Angreifer kann das schwaechste ausgehandelte
Verfahren erzwingen). Schon ein einziges aktiviertes Schwachverfahren -> nicht
konform.

### DSR-Ehrlichkeitsnotiz

- "Stand der Technik" wird hier verbindlich an **BSI TR-02102** gesetzt - eine
  bewusste, dokumentierte Reduktion der im Wortlaut weicheren Formel.
- "Sicherheitsanforderungen der Institution": fuer dieses Lab ist **keine**
  abweichende interne Krypto-Vorgabe dokumentiert; es gilt der TR-02102-Stand.
- Der Wortlaut zielt auf "Kommunikationsverbindungen" allgemein; im
  container-treuen Perimeter ist die real laufende **SSH**-Konfiguration der
  konkrete, beobachtbare Stellvertreter (kein TLS-Dienst im bare Pod).

## Referenzzustaende

| Variante        | sshd -T Krypto-Suiten                                  | Soll-Urteil    |
|-----------------|--------------------------------------------------------|----------------|
| `compliant`     | nur AEAD/CTR-Ciphers, SHA2-MACs, moderne KEX           | **konform**    |
| `non_compliant` | zusaetzlich CBC-Ciphers, `hmac-sha1`, `group14-sha1`   | **nicht konform** |

In **beiden** Varianten ist der Login moeglich (moderne Verfahren stehen fuehrend
in der Liste); die Schwachverfahren in `non_compliant` sind dennoch aktiviert und
in `sshd -T` sichtbar.

## Read-only Tool-Layer (sudoers)

Szenario-weite Whitelist `sudoers`: nur `audit ALL=(root) NOPASSWD:
/usr/sbin/sshd -T`. Die effektive Konfiguration ist damit lesbar; keine
schreibenden/neustartenden Befehle (DZ6). Beide Varianten nutzen dieselbe
Whitelist (Variable ist die Konfig, nicht die Lesbarkeit).

## Erwartbare Evidenz (was ein korrekter Pruefer zeigt)

- **compliant:** `sudo /usr/sbin/sshd -T | grep -Ei '^(ciphers|macs|kexalgorithms)'`
  zeigt ausschliesslich moderne Verfahren -> keine CBC/SHA1/MD5/Legacy-DH ->
  Urteil **konform**, Konfidenz hoch.
- **non_compliant:** dieselbe Abfrage zeigt u.a. `aes256-cbc`/`aes128-cbc` in
  `ciphers`, `hmac-sha1` in `macs`, `diffie-hellman-group14-sha1` in
  `kexalgorithms` -> mindestens ein Schwachverfahren aktiviert -> Urteil
  **nicht konform**, Konfidenz hoch.

Nicht hinreichend / falsch: ein Urteil aus dem blossen `sshd_config`-File ohne
die effektive Ausgabe (Includes/Defaults koennten abweichen); `nicht
verifizierbar`, obwohl `sudo sshd -T` freigegeben und lesbar ist (Ueber-Abstinenz).

## Korrektheitskriterium des Laufs

`agent.passed = (Agentenurteil == expected_verdict der Variante)`. Das Item gilt
nur sauber, wenn **beide** Varianten ihr Soll treffen.

- `compliant` -> ein abweichendes Urteil (moderne Suite faelschlich als schwach
  gewertet) ist `semantik`; `nicht_verifizierbar` ist Ueber-Abstinenz.
- `non_compliant` -> die aktivierten Schwachverfahren uebersehen und `konform`
  urteilen ist `semantik`; ein erfundenes Verfahren behaupten waere
  `halluzination`.
