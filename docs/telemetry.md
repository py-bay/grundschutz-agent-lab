# Telemetrie: Claude Code -> OpenObserve, pro Lauf getaggt

Ziel: jeder Agentenlauf schreibt OTel-Metriken/-Events in das
OpenObserve im Cluster (`o2.k3s.pybay.de`), getaggt mit `run.id`, sodass
sich Token, Kosten, Tool-Entscheidungen etc. **pro Lauf** und **ueber
mehrere Laeufe** auswerten lassen.

## 1. Einmalige Konfiguration (`~/.claude/settings.json`)

Diese Variablen aktivieren den Export. **Keine Secrets ins Repo** - der
Base64-Auth-String steht nur lokal in der User-`settings.json`.

```jsonc
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "https://o2.k3s.pybay.de/api/default",
    "OTEL_EXPORTER_OTLP_HEADERS": "Authorization=Basic <BASE64>",
    "OTEL_LOG_USER_PROMPTS": "1",
    "OTEL_LOG_TOOL_DETAILS": "1"
  }
}
```

Ohne die letzten beiden Flags schwaerzt Claude Code den Prompt-Text und
laesst Tool-Calls weg (Default = Privacy). `OTEL_LOG_USER_PROMPTS=1` zeigt
den Prompt, `OTEL_LOG_TOOL_DETAILS=1` Tool-Name/Befehl/Argumente. Den
Auth-Header haelt man besser aus der Datei raus und setzt ihn als
Umgebungsvariable (`OTEL_EXPORTER_OTLP_HEADERS`).

- **`<BASE64>`** erzeugen aus den OpenObserve-Admin-Creds (gleiche wie aus
  dem homelab-Vault `openobserve_admin_email` / `openobserve_admin_password`):
  `echo -n 'email:passwort' | base64 -w0`. OpenObserve nutzt **Basic**-Auth,
  nicht Bearer.
- **Endpoint:** OpenObserve ingestiert OTLP unter `/api/<org>/...`; der
  OTel-SDK haengt `/v1/metrics` bzw. `/v1/logs` an. Org-Default ist
  `default` - im o2-Web unter dem Org-Namen verifizieren.
- **Header-Format ist strikt:** `Key=Value`, keine Leerzeichen um `=`.

Gegenpruefen, dass es funkt: einen beliebigen `claude`-Lauf machen, dann im
o2-Web (`https://o2.k3s.pybay.de/web`) im Logs/Metrics-Stream auf
`claude_code.*` filtern.

## 2. Pro-Lauf-Tagging (macht `run.sh` automatisch)

`run.sh` setzt beim Vorschlagen des Agent-Kommandos:

```bash
OTEL_RESOURCE_ATTRIBUTES="run.id=<RUN_ID>,scenario=<...>,variant=<...>,requirement.id=SYS.1.3.A8" claude -p "..."
```

`OTEL_RESOURCE_ATTRIBUTES` wird von Claude Code respektiert und als
Attribut an **alle** Metriken/Events gehaengt. Damit ist jeder Lauf in
OpenObserve ueber `run.id` isolierbar und ueber `requirement.id` /
`variant` gruppierbar.

Constraints: Werte **ohne Leerzeichen** (US-ASCII, kein `" , ; \`). Das
Run-ID-Schema (`<req>__<variant>__<ts>__<rand>`) erfuellt das.

## 3. Relevante Signale

Metriken u.a.: `claude_code.token.usage`, `claude_code.cost.usage`,
`claude_code.code_edit_tool.decision`, `claude_code.active_time.total`.
Events u.a.: `claude_code.tool_decision`, `claude_code.tool_result`,
`claude_code.api_request`, `claude_code.api_error`. `prompt.id` korreliert
alle Calls eines Prompts.

Cardinality-Hinweis: `run.id` ist hochkardinal - fuer eine Forschungs-
auswertung gewollt (Pro-Lauf-Granularitaet). Default
`OTEL_METRICS_INCLUDE_RESOURCE_ATTRIBUTES=true` laesst `run.id` an den
Metriken; so bleiben Token/Kosten pro Lauf abfragbar.

## 4. Korrelation Manifest <-> Telemetrie

`runs/<run_id>/manifest.json` enthaelt `otel_resource_attributes` mit
demselben `run.id`. Damit ist der lokale Run-Nachweis (GT-Hash, Urteil,
passed) eindeutig mit der Cluster-Telemetrie verknuepft.

## 5. Was OTel erfasst - und was nicht (zwei Schichten)

Empirisch an einem Lauf geprueft (`run_id=telemetry-test`): die
claude-code-Events landen im o2-Log-Stream `default` (service_name
`claude-code`) mit u.a. den Spalten `event_name, run_id, scenario, model,
input_tokens, output_tokens, cache_*_tokens, cost_usd, duration_ms,
prompt_id, request_id, session_id`.

| Artefakt | Quelle | erfasst |
|---|---|---|
| Tokens, Kosten, Dauer, Tool-*Entscheidungen* | OTel -> o2 | ja, pro Event, getaggt mit run_id |
| Prompt-Text | OTel -> o2 | nur mit `OTEL_LOG_USER_PROMPTS=1` |
| Tool-Name/Befehl/Args | OTel -> o2 | nur mit `OTEL_LOG_TOOL_DETAILS=1` |
| **Modell-Output / Pruefurteil (Text)** | OTel -> o2 | **nein** (nur Output-Token-Zahl) |
| Tool-*Ausgabe* (z.B. `sshd -T`-Output = Evidenz) | OTel -> o2 | nur via Traces+`OTEL_LOG_TOOL_CONTENT=1` bzw. `OTEL_LOG_RAW_API_BODIES` (schwer/rauschig) |
| **Voller Record: Prompt + Antwort + Tool-I/O** | `claude -p --output-format json` / Transcript `.jsonl` | **ja, vollstaendig** |

**Designfolge:**
- **o2/OTel** = quantitative Schicht (cross-run-Aggregation: pass^k, Kosten,
  Tokens, Tool-Entscheidungen, Fehlerzaehler).
- **Pro-Lauf-Artefakt im Repo** (`runs/<run_id>/agent_output.json` +
  `transcript.jsonl`) = vollstaendige qualitative Schicht (Pruefurteil +
  Begruendung + ausgefuehrte Befehle/Evidenz) fuer GT-Abgleich und
  H3-Fehlerklassen-Codierung. `run.sh --agent` erzeugt beide automatisch.

## 6. o2 direkt abfragen (Such-API)

OpenObserve hat eine SQL-Such-API - so ziehe ich (und du) Laufdaten ohne UI:

```bash
AUTH='Authorization: Basic <BASE64>'
START=$(( $(date -u -d '24 hours ago' +%s) * 1000000 ))
END=$(( $(date -u +%s) * 1000000 ))
curl -s -X POST "https://o2.k3s.pybay.de/api/default/_search?type=logs" \
  -H "$AUTH" -H 'Content-Type: application/json' -d @- <<JSON
{ "query": {
    "sql": "SELECT event_name, model, input_tokens, output_tokens, cost_usd FROM \"default\" WHERE service_name='claude-code' AND run_id='<RUN_ID>' ORDER BY _timestamp",
    "start_time": $START, "end_time": $END, "size": 200 } }
JSON
```

Aggregation ueber Laeufe (Beispiel Kosten je Lauf):
`SELECT run_id, sum(cost_usd) c, sum(output_tokens) o FROM "default"
WHERE service_name='claude-code' GROUP BY run_id`.

## 7. Maximal-Sichtbarkeit (aktiv) + Thinking-Grenze

Aktive Flags in `~/.claude/settings.json` (zusaetzlich zu Abschnitt 1):

```jsonc
"OTEL_LOG_TOOL_CONTENT": "1",       // Tool-Ein/Ausgabe-INHALT (z.B. sshd -T-Output) in Traces, 60 KB cap
"OTEL_TRACES_EXPORTER": "otlp",     // Spans (Prompt -> API-Calls -> Tools) nach o2
"CLAUDE_CODE_ENHANCED_TELEMETRY_BETA": "1",
"OTEL_LOG_RAW_API_BODIES": "1"      // volle Request/Response-JSON in o2 (api_request_body/api_response_body), 60 KB cap
```

Damit in o2 zusaetzlich sichtbar:
- **Tool-Output-Inhalt** (Evidenz, z.B. `sshd -T`) ueber Trace-Spans.
- **Volle API-Bodies:** System-Prompt, ganze Message-History, Tool-Schemas
  (Request) und Content-Bloecke inkl. **Modell-Output-Text** (Response,
  empirisch bestaetigt). Inline = 60 KB cap (grosse Requests werden
  `body_truncated=true`); untrunkiert via `=file:<dir>` (dann aber nur
  Datei-Ref in o2, nicht der Inhalt).

**Harte Grenze - Thinking:** der Reasoning-*Text* ist **nirgends** verfuegbar
(empirisch: Transcript-Thinking-Bloecke 0/58 mit Klartext, nur `signature`;
im Raw-Response-Body steht woertlich `"thinking":"<REDACTED>"`). Auch die
Thinking-*Token-Zahl* ist **nicht separat** abgreifbar: das `usage`-Objekt
enthielt nur `input_tokens / cache_creation_input_tokens /
cache_read_input_tokens / output_tokens` (kein `thinking_tokens`-Feld) -
Thinking ist in `output_tokens` eingerechnet. Sichtbar bleibt nur `effort`
(z.B. high) + Gesamt-`output_tokens`. Fuer die Thesis als Limitation
ausweisen: interne Reasoning-Schritte sind nicht beobachtbar.

**Caveats Max-Modus:** Bodies enthalten die ganze Konversation pro Call
(Duplikation, Volumen); Tool-Inputs/Bash-Befehle/-Ausgaben koennen Secrets
enthalten (kein Auto-Scrubbing) - im kontrollierten Lab vertretbar.
