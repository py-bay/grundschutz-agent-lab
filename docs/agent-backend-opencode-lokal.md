# Agenten-Backend: opencode + Gemma lokal (souverän/offen) — DZ9

Dieser Lauf demonstriert **DZ9 (Modell-/Werkzeug-Portabilität)**: Das Prüf*instrument*
bleibt konstant, der *Agent* wird getauscht. Statt **Claude Code + Opus 4.8**
(Frontier/Cloud, Hauptlauf) läuft hier ein **vollständig lokaler, offener** Agent:
**opencode + Gemma 4 (26B) über Ollama**, alles on-device.

> **Leitsatz:** *Instrument konstant, Agent variabel.* Der Befund entsteht aus dem
> Vergleich **vorhandener Opus-Hauptlauf** ↔ **opencode+Gemma-lokal**. Es kommt
> **kein neuer Cloud-Datenpunkt** dazu; der vorhandene Opus-Hauptlauf ist der
> Vergleichsanker.

## Warum souverän-lokal kein Randthema ist

Ein agentischer BSI-Prüfer, der `/etc/shadow`-Struktur, `sshd_config` und
Auth-Policies an einen US-Cloud-LLM schickt, ist *selbst* ein Souveränitäts-/
Compliance-Problem für genau das Publikum (öffentliche Verwaltung), das Grundschutz
nutzt. Dass *dasselbe Instrument* mit einem souveränen On-Premises-Modell läuft, ist
ein echter Deployment-Befund. Bonus **DZ7**: lokale Inferenz = **null Grenzkosten,
keine Rate-Limits, kein Daten-Egress** — das Argument für kontinuierliches Monitoring.

## Der Kern: Normalisierung statt Downstream-Umbau

Der eine invariante Trick ist, dass der **Agenten-Wrapper opencodes Event-Stream in
dasselbe `agent_output.json`-Schema normalisiert**, das `claude -p --output-format
json` liefert. Damit bleibt der **gesamte Downstream byte-genau unverändert** — das
ist der eigentliche DZ9-Nachweis.

| Bleibt unverändert (Kern) | Bekommt parallelen lokalen Pfad |
|---|---|
| `run_item.sh` `extract_verdict`, `teardown.sh`, `aggregate.py` (pass^k/Konfusion/Telemetrie) | `scripts/normalize_opencode.py`: Event-Stream → `agent_output.json` |
| Prompt-Vertrag `check-prompt.md` (ohne GT) + SSH-Zugangszeile | `run.sh --backend opencode` (statt `claude -p`) |
| DZ2-Isolation (isoliertes CWD, kein GT), Manifest/Hashing | `run.sh --target docker` (Cluster nicht erreichbar) |
| **DZ6 read-only** server-seitig in der Target-`sudoers`-Whitelist | — (providerunabhängig, der Swap schwächt DZ6 nicht) |

`run.sh` und `teardown.sh` wurden **rein additiv** erweitert (`--target k8s|docker`,
`--backend claude|opencode`); die Defaults (`k8s` + `claude`) verhalten sich
unverändert.

## Normalisierungs-Mapping (opencode → Claude-Schema)

opencode `run --format json` liefert zeilenweise JSON-Events
(`step_start | tool_use | text | step_finish`). `normalize_opencode.py` bildet ab:

| `agent_output.json` (Claude-Schema) | Quelle im opencode-Event-Stream | Anmerkung |
|---|---|---|
| `result` | Konkatenation aller `text`-Parts | Das Urteil; `extract_verdict` scannt es |
| `total_cost_usd` | `0` (fix) | Lokale Inferenz: echte Null-Grenzkosten (DZ7) |
| `num_turns` | Anzahl `step_finish` | Analog zu Claude-`num_turns` (Assistenz-Schritte) |
| `duration_ms` | Wall-Clock der `opencode run`-Invocation | inkl. evtl. Modell-Kaltladen beim ersten Lauf |
| `usage.input_tokens` | **max** `step_finish.part.tokens.input` | Spitzen-Kontext (interpretierbarer als die Summe) |
| `usage.output_tokens` | **Summe** `step_finish.part.tokens.output` | gesamte Generierung |
| `usage.cache_read_input_tokens` | `0` | lokal kein Prompt-Cache — echter, berichtbarer Unterschied |
| `is_error` | `rc != 0` **oder** leere Endantwort | aggregate.py liest `is_error` |
| `tool_calls`, `model`, `model_digest`, `backend` | Provenance-Block | Downstream braucht ihn nicht |

**Token-Vergleichbarkeit:** Cross-Backend-Tokenzahlen sind nur grob vergleichbar
(andere Tokenizer, kein Prompt-Cache lokal). Das ist hier bewusst ausgewiesen, nicht
kaschiert. `usage.input_tokens_cumulative` hält zusätzlich die Summe aller
Step-Inputs (das, was Ollama ohne Cache real evaluiert hat).

## Architektur: lokaler Agent (Laptop) + lokales Docker-Target

- **RAM-Constraint:** Ollama + Gemma laufen auf dem **Laptop**. opencode↔Ollama über
  `localhost:11434`, opencode↔Target über SSH auf `127.0.0.1:<port>`.
- **Target = lokaler Docker-Container** statt k3s-Pod. Bewusste, dokumentierte
  Abweichung vom Hauptlauf-Substrat: der **k3s-Cluster war nicht erreichbar**
  (öffentliche IP vermutlich gebannt). Der Container-Bootstrap
  (`scripts/target-bootstrap.sh`) ist **inhaltlich wortgleich** zum Pod-Template
  (`kubernetes/target-pod.tmpl.yaml`): gleiches Image `ubuntu:24.04`, gleicher
  openssh-Bootstrap, gleicher `audit`-User, gleiche read-only `sudoers`-Whitelist,
  gleiche `setup.sh`-Etablierung. Für **statische Konfig-Anforderungen** (hier
  SYS.1.1.A2, SYS.2.1.A18) ist ein bare-Container faithful (vgl. Labor-Treue).
- **Permissions headless:** `"ask"` hängt (opencode #14473) → `--dangerously-skip-permissions`.
  Read-only liegt ohnehin server-seitig in der Target-`sudoers`-Whitelist (DZ6).

## Telemetrie-Rahmen (Grenzen ehrlich)

- **Kein OTel.** opencode hat (Stand 1.17.x, #14697) keinen OpenTelemetry-Export wie
  Claude Code. Die Telemetrie kommt daher **aus dem normalisierten
  `agent_output.json`** (Kosten=0, Tokens, Schritte, Dauer), nicht aus OpenObserve.
- **Kosten = 0** (echt, lokal). **Dauer** = Wall-Clock (CPU/iGPU-Inferenz, kein
  CUDA-GPU → entsprechend langsamer als Cloud).

## Reproduzierbarkeits-Pins

| Komponente | Pin |
|---|---|
| opencode | `1.17.11` (`npm i -g opencode-ai@1.17.11`) |
| Ollama | `0.24.0` |
| Modell | `gemma4:26b-32k`, Quantisierung **Q4_K_M**, Manifest-Digest `sha256:8ab8e8b44290…`, Basis-Blob `sha256:7121486771cb…` |
| Modell-Parameter | `num_ctx 32768`, `temperature 1`, `top_k 64`, `top_p 0.95` (Ollama-Modelfile) |
| opencode-Config | `config/opencode.json` (Ollama-Provider, `gemma4:26b-32k`, `tools:true`) |
| Laptop-Hardware | AMD Ryzen AI 9 HX PRO 370 (24 Threads), Radeon 890M iGPU, 54 GiB RAM, **keine NVIDIA-GPU** (CPU/iGPU-Inferenz) |

> **Reproduzierbarkeits-Caveat:** `temperature 1` (Modell-Default) → Lauf-zu-Lauf-
> Varianz. Die Läufe hier sind **k=1, exploratorisch**; für eine summative
> Aussage müsste die Temperatur gepinnt und k erhöht werden.

## Aufruf

```bash
# Lokaler Souveränitätslauf: docker-Target + opencode/Gemma
scripts/run.sh <scenario-id> <variant> --target docker --backend opencode --port <PORT>
# danach Urteil festhalten + Container abräumen
scripts/teardown.sh <run_id> --verdict <konform|nicht_konform|nicht_verifizierbar>
```

Optionale Env-Overrides: `OPENCODE_MODEL` (Default `ollama/gemma4:26b-32k`),
`OPENCODE_VARIANT` (Reasoning-Effort), `OPENCODE_DIGEST` (Modell-Digest für die
Provenance im Artefakt).

## Ergebnisse (k=1, Head-to-Head gegen Opus-Hauptlauf)

**Befund in einem Satz:** Das Instrument läuft unverändert auf einem vollständig
souveränen, lokalen Stack (`opencode` + `gemma4:26b` + Docker-Target), und es **misst
die Lücke**: Das offene lokale Modell hält die **Abstinenz-Disziplin** des Frontier-
Modells (Ergebnisklasse 4), **degradiert** aber bei der **semantischen Krypto-
Bewertung** (Ergebnisklasse 1) — `3/4` Prüffälle korrekt.

### Urteil (Soll vs. Ist) — 4 Prüffälle, k=1

| Anforderung × Variante (EK) | Soll | Opus 4.8 (Cloud, k=4) | gemma4:26b (lokal, k=1) | Match |
|---|---|---|---|---|
| SYS.1.1.A2 · `locked` (EK4, **Abstinenz**) | `nicht_verifizierbar` | `nicht_verifizierbar` (4/4, pass⁴=1,0) | **`nicht_verifizierbar`** ✓ | = |
| SYS.1.1.A2 · `readable` (EK4) | `konform` | `konform` (4/4, pass⁴=1,0) | **`konform`** ✓ | = |
| SYS.2.1.A18 · `compliant` (EK1) | `konform` | `konform` (Hauptlauf) | **`nicht_konform`** ✗ | ≠ |
| SYS.2.1.A18 · `non_compliant` (EK2) | `nicht_konform` | `nicht_konform` (Hauptlauf) | **`nicht_konform`** ✓ | = |

`aggregate.py --backend opencode` (Maschinenausgabe: `runs/_index/dz9-opencode-summary.json`):
4 Läufe, **3 bestanden**, eine Fehlklassifikation. Konfusionsmatrix (Zeile=Soll):

```
Soll\Ist             konform  nicht_konform  nicht_verifizierbar
konform                 1          1                 0        <- A18 compliant: Falsch-Positiv
nicht_konform           0          1                 0
nicht_verifizierbar     0          0                 1        <- A2 locked: korrekte Abstinenz
```

### Telemetrie je Prüfung

| Backend (Modell) | Kosten/Lauf | Dauer/Lauf | num_turns | Tokens (in peak / out) | Prompt-Cache | OTel |
|---|---|---|---|---|---|---|
| Claude Code + Opus 4.8 (Cloud) | ~0,2–0,6 USD | ~1–2 min (API) | 4–6 | gecacht (cache-read groß) | ja | ja (OpenObserve) |
| opencode + gemma4:26b (lokal, iGPU) | **0 USD** (n=4) | 123–198 s (⌀ 163 s) | 3–4 | in 8143–9185 / out 940–2132 | **nein** | **nein** (#14697) |

### Argumentationsgüte (kein Glückstreffer — und der eine echte Fehler)

- **A2 `locked` (Abstinenz, korrekt):** `sudo -l` → `ls -l /etc/{passwd,shadow,login.defs}`
  → `sudo /usr/bin/stat /etc/shadow`. Das Modell erkannte, dass nur **Metadaten**
  zugänglich sind: *„die tatsächlich eingesetzten Credentials … sind nicht prüfbar, da
  der Zugriff auf den Inhalt von `/etc/shadow` … nicht möglich ist."* → `nicht
  verifizierbar`, Konfidenz hoch. Es fiel **nicht** auf den welt-lesbaren
  `login.defs`-Stellvertreter herein.
- **A2 `readable` (konform, korrekt):** `sudo /usr/bin/cat /etc/shadow` → las den realen
  `$y$`-yescrypt-Hash von `svcadmin`, keine leeren Passwörter → `konform`.
- **A18 `non_compliant` (nicht konform, korrekt — aus den richtigen Gründen):** fand im
  **echten** Suite-Satz `diffie-hellman-group14-sha1`, `hmac-sha1` und CBC-Cipher
  (`aes256-cbc`) → real TR-02102-widrig.
- **A18 `compliant` (Falsch-Positiv — der diagnostische Fehler):** Der reale
  `kexalgorithms`/`ciphers`/`macs`-Satz war modern. Das Modell griff aber die **inerte**
  Zeile `gssapikexalgorithms … gss-group14-sha1-` (nur bei aktiviertem GSSAPI relevant,
  hier aus) auf und wertete deren SHA-1 als Verstoß → `nicht konform`. **Semantik-Fehler
  durch Über-Strenge**, keine Halluzination (die Strings existieren) — das Modell kann
  *aktive* nicht von *inerter* Konfiguration trennen. Genau diese Lücke macht das
  Instrument **messbar**.

### Nuance (wertvoll für die Diskussion)

Die Plan-Hypothese war *„ein kleines lokales Modell scheitert am ehesten an der
Abstinenz"*. Tatsächlich war es **umgekehrt**: Das lokale 26B-Modell traf die
**Abstinenz** korrekt (ein **kleineres Cloud-Modell, Haiku-Pilot, k=1**, verfehlte
denselben Fall einmal mit `nicht_konform`), scheiterte aber an der **semantischen
Krypto-Bewertung** des sauber-konformen Falls. **„Klein" allein ist nicht der
Prädiktor**; der Schwachpunkt des offenen Modells liegt im *kontextuellen Abwägen*
(aktiv vs. inert), nicht in der Abstinenz-Vorsicht.

### Grenzen dieses Datenpunkts (ehrlich)

- **k=1, `temperature 1`** (Einzelstichprobe) gegen den Opus-Baseline **k=4** — ein
  **exploratorischer** Souveränitäts-Datenpunkt, **keine summative** Aussage. Das
  A18-`compliant`-Falsch-Positiv könnte bei k>1 streuen.
- **Confound:** Modell **und** Werkzeug **und** Betriebsmodell **und** Ziel-Substrat
  (Docker statt k3s) wechseln gemeinsam — als bewusste Abweichung ausgewiesen.
- **Kleine Modell-Lockerheit:** in `locked` und `compliant` gab das Modell beim
  Abschreiben von Befehlsausgaben einzelne Tokens ungenau wieder (z.B. `curve255im256`
  statt `curve25519-sha256@libssh.org`); die **Urteile** stützten sich auf real
  vorhandene Belege. Hinweis auf geringere Transkriptionstreue, ohne die Urteile zu kippen.
- **Substrat-Treue:** bare-Container statt Pod ist für **statische Konfig-Anforderungen**
  (A2, A18) faithful; Host/Kernel-/Laufzeit-Anforderungen wären es nicht.
