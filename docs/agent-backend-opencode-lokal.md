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

## Ergebnisse (k=4, k3s-Substrat — sauberes Head-to-Head gegen den Opus-Hauptlauf)

> Sauberer Lauf: **identisches k3s-Pod-Substrat** wie der Opus-Hauptlauf, Agent +
> Modell auf dem Laptop (`--target k8s --backend opencode`), **k=4** wie der
> Hauptlauf. Nur der Agent ist getauscht — kein Substrat-Confound. Der frühere
> Docker/k=1-Lauf (s.u.) bleibt als explorative Vorstufe erhalten.

**Befund in einem Satz:** Das Instrument läuft unverändert auf einem souveränen,
lokalen Stack und **misst eine klare Zuverlässigkeitslücke**: Das offene lokale
Modell ist **stabil, wo das Soll „abstiniere" oder „nicht konform" ist** (8/8), aber
**unzuverlässig, wo das Soll `konform` ist** (3/8) — eine **konservative Über-
Flagging-Tendenz**. Das ist das *Gegenteil* der üblichen Sorge: Das Modell
halluziniert nicht *Konformität*, es verweigert sie.

### pass^k je Prüffall (k=4)

| Anforderung × Variante (EK) | Soll | Opus 4.8 (Cloud) | gemma4:26b (lokal) | pass⁴ lokal |
|---|---|---|---|---|
| SYS.1.1.A2 · `locked` (EK4, Abstinenz) | `nicht_verifizierbar` | pass⁴=1,0 | `nv`×4 → **4/4** | **1,0 ✓** |
| SYS.1.1.A2 · `readable` (EK4) | `konform` | pass⁴=1,0 | `konform`×1, `nicht_konform`×2, `nv`×1 → **1/4** | **0** |
| SYS.2.1.A18 · `compliant` (EK1) | `konform` | pass⁴=1,0 | `konform`×2, `nicht_konform`×2 → **2/4** | **0** |
| SYS.2.1.A18 · `non_compliant` (EK2) | `nicht_konform` | pass⁴=1,0 | `nicht_konform`×4 → **4/4** | **1,0 ✓** |

`aggregate.py --backend opencode --target k8s` (Maschinenausgabe:
`runs/_index/dz9-opencode-k8s-k4-summary.json`): 16 Läufe. Konfusionsmatrix (Zeile=Soll):

```
Soll\Ist             konform  nicht_konform  nicht_verifizierbar
konform                 3          4                 1     <- Soll konform: nur 3/8 getroffen
nicht_konform           0          4                 0     <- 4/4
nicht_verifizierbar     0          0                 4     <- 4/4 korrekte Abstinenz
```

Gegen den Opus-Hauptlauf (pass⁴=1,0 auf allen vier Fällen) erreicht das offene lokale
Modell pass⁴=1,0 nur auf den beiden „nicht-konform/abstinenz"-Fällen.

### Die Fehlermodi sind charakterisierbar (nicht zufällig)

Alle Fehlklassifikationen liegen auf der **`konform`-Seite** und zeigen dieselbe
konservative Tendenz:

- **`readable` — Semantik-Inversion:** Ein Lauf wertete `root:*` in `/etc/shadow` als
  *„leeres Passwort"* und damit als Verstoß. `*` heißt aber **gesperrt** (kein
  Passwort-Login), nicht leer — eine invertierte Lesart, die einen Nicht-Konform-
  Befund erfindet → `nicht konform`.
- **`readable` — Über-Argumentation:** Ein anderer Lauf erkannte den starken
  `svcadmin`-yescrypt-Hash und die per `!` gesperrten Konten korrekt, spiralte dann
  aber in *„Angemessenheit/MFA für alle Konten nicht beweisbar"* und redete sich in
  `nicht konform` (inkl. selbstkorrigierender *„Finaler Fokus"*-Passage) — Über-
  Strenge plus instabile Schlusskette.
- **A18 `compliant` — Über-Flagging einer inerten Konfig (2/4, kein stabiler Fehler):**
  Bei der Hälfte der Läufe griff das Modell die **inerte** Zeile
  `gssapikexalgorithms … gss-group14-sha1-` (nur bei aktiviertem GSSAPI relevant, hier
  aus) auf und wertete deren SHA-1 als Verstoß; der reale `kexalgorithms`/`ciphers`/
  `macs`-Satz war modern. Das Modell trennt *aktive* nicht zuverlässig von *inerter*
  Konfiguration.
- **Korrekt aus den richtigen Gründen:** `non_compliant` (4/4) fand stets die **echt**
  schwachen Verfahren (`diffie-hellman-group14-sha1`, `hmac-sha1`, CBC); `locked` (4/4)
  abstinierte stets korrekt mangels lesbarer `/etc/shadow`-Evidenz.

### Methodischer Befund: k=1 hätte getäuscht

Der explorative **Docker/k=1**-Lauf ergab `3/4` und ließ das lokale Modell wie einen
sauberen Beinahe-Match zum Frontier-Modell aussehen (`readable` traf zufällig
`konform`, A18-`compliant` sah aus wie ein stabiler Einzelfehler). Erst **k=4** macht
die Streuung sichtbar (`readable` 1/4, `compliant` 2/4). **Für eine belastbare DZ9/
DZ4-Aussage ist k>1 nötig**; pass^k ist hier nicht nur Metrik, sondern Voraussetzung,
um die Zuverlässigkeitslücke überhaupt zu sehen.

### Telemetrie je Prüfung (16 k3s/k=4-Läufe)

| Backend (Modell) | Kosten/Lauf | Dauer/Lauf | num_turns | Tokens (in peak / out) | Prompt-Cache | OTel |
|---|---|---|---|---|---|---|
| Claude Code + Opus 4.8 (Cloud) | ~0,2–0,6 USD | ~1–2 min (API) | 4–6 | gecacht (cache-read groß) | ja | ja (OpenObserve) |
| opencode + gemma4:26b (lokal, iGPU) | **0 USD** | 123–284 s (⌀ ~189 s) | 3–8 | in 8126–9969 / out 762–2132 | **nein** | **nein** (#14697) |

### Grenzen (ehrlich)

- **`temperature 1`** (Modell-Default) ist die Hauptquelle der Streuung; ein gepinntes,
  niedrigeres `temperature` würde die `konform`-Instabilität vermutlich dämpfen — das
  ist ein Tuning-Befund, kein prinzipielles Limit. Hier bewusst Modell-Default belassen.
- **Confound bleibt teilweise:** Modell **und** Werkzeug **und** Betriebsmodell wechseln
  gemeinsam (das Substrat ist jetzt aber identisch zum Hauptlauf). Es ist ein
  Agent-Gesamtpaket-Vergleich, keine Einzelfaktor-Isolation.
- **Transkriptionstreue:** das Modell gab Befehlsausgaben gelegentlich ungenau wieder
  (z.B. `curve255im256` statt `curve25519-sha256@libssh.org`); die Urteile stützten
  sich auf real vorhandene Belege.
- **Substrat-Treue:** bare-Pod ist für **statische Konfig-Anforderungen** (A2, A18)
  faithful; Host/Kernel-/Laufzeit-Anforderungen wären es nicht.

### Frühere explorative Vorstufe (Docker/k=1)

Der erste Durchstich lief mangels Cluster-Erreichbarkeit auf einem **lokalen
Docker-Target** mit **k=1** (`runs/_index/dz9-opencode-summary.json`): `3/4` korrekt
(`locked` `nv` ✓, `readable` `konform` ✓, A18 `compliant` `nicht_konform` ✗, A18
`non_compliant` `nicht_konform` ✓). Durch den späteren sauberen k3s/k=4-Lauf als
*explorativ überholt* einzuordnen; er belegt zusätzlich, dass der Wrapper auch auf dem
Container-Substrat trägt.
