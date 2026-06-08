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
    "OTEL_EXPORTER_OTLP_HEADERS": "Authorization=Basic <BASE64>"
  }
}
```

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
