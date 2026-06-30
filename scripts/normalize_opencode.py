#!/usr/bin/env python3
"""normalize_opencode.py - normalisiert opencodes JSON-Event-Stream (`opencode run
--format json`) in DASSELBE agent_output.json-Schema, das `claude -p
--output-format json` liefert. Damit bleibt der Downstream (run_item.sh
extract_verdict, teardown.sh, aggregate.py) BYTE-genau unveraendert - das ist der
Kern des DZ9-Nachweises (Modell-/Werkzeug-Portabilitaet bei konstantem Instrument).

opencode-Eventschema (1.17.x, je Zeile ein JSON-Objekt):
  {type, timestamp(ms), sessionID, part}
  - type=step_start  : neuer Assistenz-Schritt
  - type=tool_use    : part.tool, part.state.input/output/metadata.exit
  - type=text        : part.text (Teil der Endantwort)
  - type=step_finish : part.reason, part.tokens{total,input,output,reasoning,
                       cache{read,write}}, part.cost

Telemetrie-Mapping (bewusst, dokumentiert in docs/agent-backend-opencode-lokal.md):
  result        = Konkatenation aller text-Parts (das Urteil; extract_verdict scannt es)
  total_cost_usd= 0   (lokale Inferenz, echte Null-Grenzkosten - DZ7)
  num_turns     = Zahl der step_finish (Assistenz-Schritte; Analog zu claude num_turns)
  duration_ms   = Wall-Clock der opencode-Invocation (--wall-ms; inkl. evtl. Kaltladen)
  usage.input_tokens          = MAX step-input (Spitzen-Kontext; interpretierbarer
                                 als die Summe, die ohne Prompt-Cache nur die
                                 wiederholten Re-Sends aufaddiert)
  usage.output_tokens         = Summe der step-outputs (gesamte Generierung)
  usage.cache_read_input_tokens = 0   (lokal kein Prompt-Cache - echter, berichtbarer
                                       Unterschied zum Frontier-Lauf)
Cross-Backend-Tokenzahlen sind nur grob vergleichbar (andere Tokenizer, kein Cache);
das ist in der Telemetrie-Doku ausgewiesen.

Aufruf:
  normalize_opencode.py --events events.jsonl --wall-ms 89123 --rc 0 \
      --model ollama/gemma4:26b-32k [--model-digest sha256:...] > agent_output.json
"""
import argparse
import json
import sys


def load_events(path):
    events = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                # opencode kann vereinzelt Nicht-JSON-Zeilen (Warnungen) mischen;
                # die ueberspringen statt den ganzen Lauf zu verlieren.
                continue
    return events


def main():
    ap = argparse.ArgumentParser(description="opencode-Eventstream -> claude-agent_output.json")
    ap.add_argument("--events", required=True, help="Pfad zur opencode events.jsonl")
    ap.add_argument("--wall-ms", type=int, default=None, help="Wall-Clock der Invocation in ms")
    ap.add_argument("--rc", type=int, default=0, help="Exit-Code von opencode run")
    ap.add_argument("--model", default="", help="provider/model, z.B. ollama/gemma4:26b-32k")
    ap.add_argument("--model-digest", default="", help="Ollama-Modell-Digest (Reproduzierbarkeit)")
    args = ap.parse_args()

    events = load_events(args.events)

    text_parts = []
    tool_calls = 0
    step_finishes = []
    step_inputs = []
    step_outputs = []
    session_id = None
    first_ts = last_ts = None
    last_reason = None

    for ev in events:
        t = ev.get("type")
        part = ev.get("part") or {}
        ts = ev.get("timestamp")
        if ts is not None:
            first_ts = ts if first_ts is None else min(first_ts, ts)
            last_ts = ts if last_ts is None else max(last_ts, ts)
        if not session_id:
            session_id = ev.get("sessionID") or part.get("sessionID")
        if t == "text":
            txt = part.get("text")
            if txt:
                text_parts.append(txt)
        elif t == "tool_use":
            tool_calls += 1
        elif t == "step_finish":
            step_finishes.append(part)
            last_reason = part.get("reason") or last_reason
            tok = part.get("tokens") or {}
            if tok.get("input") is not None:
                step_inputs.append(tok["input"])
            if tok.get("output") is not None:
                step_outputs.append(tok["output"])

    result_text = "".join(text_parts).strip()
    num_turns = len(step_finishes)
    input_peak = max(step_inputs) if step_inputs else 0
    input_cumulative = sum(step_inputs) if step_inputs else 0
    output_sum = sum(step_outputs) if step_outputs else 0
    model_ms = (last_ts - first_ts) if (first_ts is not None and last_ts is not None) else None

    # Fehlerfall: opencode-Abbruch ODER keine Endantwort produziert -> downstream
    # soll das als is_error sehen (aggregate.py liest is_error).
    is_error = bool(args.rc != 0 or not result_text)

    out = {
        "type": "result",
        "subtype": "error" if is_error else "success",
        "is_error": is_error,
        "result": result_text,
        "num_turns": num_turns,
        "duration_ms": args.wall_ms if args.wall_ms is not None else model_ms,
        "total_cost_usd": 0,
        "usage": {
            "input_tokens": input_peak,
            "output_tokens": output_sum,
            "cache_read_input_tokens": 0,
            "cache_creation_input_tokens": 0,
            "input_tokens_cumulative": input_cumulative,
        },
        "session_id": session_id,
        "stop_reason": last_reason,
        # Provenance-Block: macht die Herkunft im normalisierten Artefakt explizit,
        # ohne dass der Downstream ihn braucht.
        "backend": "opencode",
        "model": args.model,
        "model_digest": args.model_digest or None,
        "tool_calls": tool_calls,
        "model_ms": model_ms,
        "modelUsage": {
            (args.model or "unknown"): {
                "inputTokens": input_peak,
                "inputTokensCumulative": input_cumulative,
                "outputTokens": output_sum,
                "costUSD": 0,
            }
        },
        "permission_denials": [],
        "rc": args.rc,
    }
    json.dump(out, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
