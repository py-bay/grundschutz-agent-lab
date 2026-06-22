#!/usr/bin/env python3
"""aggregate.py - wertet die Lauf-Artefakte (runs/<id>/manifest.json +
agent_output.json) zu den Berichts-Kennzahlen des Hauptlaufs aus:

  - pass^k je (Anforderung x Variante) und je Ergebnisklasse (DZ5),
  - deskriptive 3x3-Konfusionsmatrix Soll x Ist (DZ4),
  - Abstinenz-Rate (Anteil nicht_verifizierbar),
  - Telemetrie je Pruefung (Kosten, Tokens, Dauer, Schritte; DZ7).

Das Lab liefert nur die Roh-Aggregation. Figuren/ICR fuer die Thesis leben in
`bsi-grundschutz-classification`.

Liest BEIDE Feldnamen der Ergebnisklasse (`ergebnisklasse` neu, `cell` alt) und
faellt fuer alte A8-Manifeste von `expected_verdict` auf `expected_compliant`
zurueck. Reine Standardbibliothek.

Aufruf:
  scripts/aggregate.py [--runs-dir runs] [--requirement SYS.2.3.A1]
                       [--scenario <id>] [--ergebnisklasse 4_fehlende_berechtigung]
                       [--k 4] [--json out.json]
"""
import argparse
import glob
import json
import os
import statistics
import sys
from collections import defaultdict, OrderedDict

VERDICTS = ["konform", "nicht_konform", "nicht_verifizierbar"]
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def derive_expected(m):
    ev = m.get("expected_verdict")
    if ev:
        return ev
    ec = m.get("expected_compliant", None)
    if ec is True:
        return "konform"
    if ec is False:
        return "nicht_konform"
    if ec is None and "expected_compliant" in m:
        return "nicht_verifizierbar"
    return None


def load_runs(runs_dir, flt):
    runs = []
    for mpath in sorted(glob.glob(os.path.join(runs_dir, "*", "manifest.json"))):
        try:
            with open(mpath, encoding="utf-8") as fh:
                m = json.load(fh)
        except Exception as exc:  # defekte/halbe Manifeste ueberspringen, aber melden
            print(f"WARN: {mpath} nicht lesbar ({exc})", file=sys.stderr)
            continue
        ek = m.get("ergebnisklasse") or m.get("cell") or "?"
        rec = {
            "run_id": m.get("run_id") or os.path.basename(os.path.dirname(mpath)),
            "requirement_id": m.get("requirement_id", "?"),
            "scenario": m.get("scenario", "?"),
            "variant": m.get("variant", "?"),
            "ergebnisklasse": ek,
            "category": m.get("category", "?"),
            "expected": derive_expected(m),
            "phase": m.get("phase", "?"),
            "verdict": (m.get("agent") or {}).get("verdict"),
            "passed": (m.get("agent") or {}).get("passed"),
            "dir": os.path.dirname(mpath),
        }
        if flt["requirement"] and rec["requirement_id"] != flt["requirement"]:
            continue
        if flt["scenario"] and rec["scenario"] != flt["scenario"]:
            continue
        if flt["ergebnisklasse"] and rec["ergebnisklasse"] != flt["ergebnisklasse"]:
            continue
        rec["telemetry"] = load_telemetry(rec["dir"])
        runs.append(rec)
    return runs


def load_telemetry(run_dir):
    p = os.path.join(run_dir, "agent_output.json")
    if not os.path.isfile(p):
        return {}
    try:
        with open(p, encoding="utf-8") as fh:
            a = json.load(fh)
    except Exception:
        return {}
    usage = a.get("usage") or {}
    return {
        "cost_usd": a.get("total_cost_usd"),
        "num_turns": a.get("num_turns"),
        "duration_ms": a.get("duration_ms"),
        "input_tokens": usage.get("input_tokens"),
        "output_tokens": usage.get("output_tokens"),
        "cache_read_tokens": usage.get("cache_read_input_tokens"),
        "is_error": a.get("is_error"),
    }


def fmt_pct(x):
    return "-" if x is None else f"{100*x:.0f}%"


def group_passk(runs, k):
    """pass^k je (Anforderung, Variante, Ergebnisklasse). Nur Laeufe mit
    gesetztem passed zaehlen als gewertet."""
    groups = OrderedDict()
    for r in runs:
        key = (r["requirement_id"], r["variant"], r["ergebnisklasse"], r["expected"])
        g = groups.setdefault(key, {"n": 0, "scored": 0, "passed": 0,
                                    "verdicts": defaultdict(int)})
        g["n"] += 1
        if r["verdict"]:
            g["verdicts"][r["verdict"]] += 1
        if r["passed"] is not None:
            g["scored"] += 1
            if r["passed"]:
                g["passed"] += 1
    rows = []
    for (req, var, ek, exp), g in groups.items():
        rate = (g["passed"] / g["scored"]) if g["scored"] else None
        all_pass = (g["scored"] >= 1 and g["passed"] == g["scored"])
        rows.append({
            "requirement": req, "variant": var, "ergebnisklasse": ek,
            "expected": exp, "n": g["n"], "scored": g["scored"],
            "passed": g["passed"], "pass_rate": rate,
            "passk_strict": bool(all_pass and g["scored"] >= 1),
            "k_target": k,
            "verdicts": dict(g["verdicts"]),
        })
    return rows


def confusion(runs):
    mtx = {s: {i: 0 for i in VERDICTS} for s in VERDICTS}
    other = 0
    for r in runs:
        s, i = r["expected"], r["verdict"]
        if s in mtx and i in VERDICTS:
            mtx[s][i] += 1
        elif i:  # gewertet, aber ausserhalb des Schemas / Soll unbekannt
            other += 1
    return mtx, other


def ek_rollup(runs):
    by = OrderedDict()
    for r in runs:
        g = by.setdefault(r["ergebnisklasse"], {"n": 0, "scored": 0, "passed": 0,
                                                "abst": 0})
        g["n"] += 1
        if r["passed"] is not None:
            g["scored"] += 1
            g["passed"] += 1 if r["passed"] else 0
        if r["verdict"] == "nicht_verifizierbar":
            g["abst"] += 1
    return by


def telemetry_summary(runs):
    def col(name):
        return [r["telemetry"].get(name) for r in runs
                if r["telemetry"].get(name) is not None]
    out = {}
    for name in ["cost_usd", "num_turns", "duration_ms", "output_tokens",
                 "input_tokens", "cache_read_tokens"]:
        vals = col(name)
        if vals:
            out[name] = {"n": len(vals), "mean": statistics.mean(vals),
                         "median": statistics.median(vals),
                         "min": min(vals), "max": max(vals), "sum": sum(vals)}
    return out


def main():
    ap = argparse.ArgumentParser(description="Lab-Run-Aggregation (pass^k, Konfusionsmatrix, Telemetrie)")
    ap.add_argument("--runs-dir", default=os.path.join(REPO_ROOT, "runs"))
    ap.add_argument("--requirement", default=None)
    ap.add_argument("--scenario", default=None)
    ap.add_argument("--ergebnisklasse", default=None)
    ap.add_argument("--k", type=int, default=4)
    ap.add_argument("--json", default=None, help="Pfad fuer maschinenlesbare Ausgabe")
    args = ap.parse_args()

    flt = {"requirement": args.requirement, "scenario": args.scenario,
           "ergebnisklasse": args.ergebnisklasse}
    runs = load_runs(args.runs_dir, flt)
    if not runs:
        print("Keine passenden Laeufe gefunden.", file=sys.stderr)
        return 1

    scored = [r for r in runs if r["passed"] is not None]
    with_verdict = [r for r in runs if r["verdict"]]
    incomplete = [r for r in runs if r["passed"] is None]

    print(f"== Ueberblick ==  Laeufe={len(runs)}  gewertet(passed!=null)={len(scored)}  "
          f"mit Urteil={len(with_verdict)}  unvollstaendig={len(incomplete)}")
    if incomplete:
        print("  unvollstaendig (kein agent.passed): "
              + ", ".join(r["run_id"] for r in incomplete))

    print("\n== pass^k je (Anforderung x Variante x Ergebnisklasse) ==")
    print(f"{'Anforderung':<14}{'Variante':<14}{'EK':<24}{'Soll':<20}"
          f"{'n':>3}{'gew':>4}{'pass':>5}{'rate':>6}  pass^k  Urteile")
    passk_rows = group_passk(runs, args.k)
    for row in passk_rows:
        verd = ",".join(f"{v}:{n}" for v, n in sorted(row["verdicts"].items()))
        print(f"{row['requirement']:<14}{row['variant']:<14}{row['ergebnisklasse']:<24}"
              f"{str(row['expected']):<20}{row['n']:>3}{row['scored']:>4}{row['passed']:>5}"
              f"{fmt_pct(row['pass_rate']):>6}  {'JA' if row['passk_strict'] else '-':<6}  {verd}")

    print("\n== Ergebnisklassen-Rollup ==")
    for ek, g in ek_rollup(runs).items():
        rate = (g["passed"] / g["scored"]) if g["scored"] else None
        print(f"  {ek:<26} n={g['n']:<3} gewertet={g['scored']:<3} "
              f"pass={g['passed']} ({fmt_pct(rate)})  abstinenz(nicht_verifizierbar)={g['abst']}")

    print("\n== Konfusionsmatrix (Zeile=Soll, Spalte=Ist) ==")
    mtx, other = confusion(runs)
    hdr = "Soll\\Ist".ljust(22) + "".join(v[:14].ljust(16) for v in VERDICTS)
    print("  " + hdr)
    for s in VERDICTS:
        print("  " + s.ljust(22) + "".join(str(mtx[s][i]).ljust(16) for i in VERDICTS))
    if other:
        print(f"  (zusaetzlich {other} Laeufe mit Urteil ausserhalb Schema/ohne Soll-Mapping)")

    print("\n== Telemetrie (ueber Laeufe mit agent_output.json) ==")
    tsum = telemetry_summary(runs)
    if not tsum:
        print("  (keine Telemetrie gefunden)")
    for name, s in tsum.items():
        print(f"  {name:<18} n={s['n']:<3} mean={s['mean']:.4g} median={s['median']:.4g} "
              f"min={s['min']:.4g} max={s['max']:.4g} sum={s['sum']:.4g}")

    if args.json:
        out = {
            "filter": flt,
            "counts": {"runs": len(runs), "scored": len(scored),
                       "with_verdict": len(with_verdict), "incomplete": len(incomplete)},
            "passk": passk_rows,
            "ergebnisklassen": {ek: g for ek, g in ek_rollup(runs).items()},
            "confusion": mtx, "confusion_other": other,
            "telemetry": tsum,
            "runs": [{k: r[k] for k in ("run_id", "requirement_id", "variant",
                                        "ergebnisklasse", "expected", "verdict",
                                        "passed", "phase")} for r in runs],
        }
        outdir = os.path.dirname(os.path.abspath(args.json))
        os.makedirs(outdir, exist_ok=True)
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(out, fh, indent=2, ensure_ascii=False)
        print(f"\nJSON geschrieben: {args.json}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
