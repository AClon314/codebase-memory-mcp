#!/usr/bin/env python3
"""A0.5: compare cbm-native and SCIP-writer CALLS on the hard fixture.

Usage:
  python3 evaluate.py <cbm.db> <scip.db> [--json]

The fixture's semantic ground truth separates callable-level calls from
module-level calls. Module/import/export/extends edges are reported separately
because the SCIP writer currently emits some of them as CALLS; they are not
part of the function call-graph score.
"""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
from pathlib import Path

# Source is a named function/method; target may be a Class for `new`.
FUNCTION_GT = {
    ("useAlias", "UserRepo"),
    ("useAlias", "get"),
    ("useGeneric", "identity"),
    ("useCond", "load"),
    ("useHof", "apply"),
    ("useHof", "helper"),
    ("useOverload", "pick"),
    ("get", "load"),
    ("load", "make"),
    ("go", "get"),
    ("go", "helper"),
}

# `new UserRepo()` at Svelte module top level. Kept out of FUNCTION_GT because
# the source is not a callable.
MODULE_GT = {("Comp.svelte", "UserRepo"), ("Comp.svelte", "go")}

QUERY = """
SELECT a.label AS source_label,
       a.name AS source_name,
       a.file_path AS source_file,
       b.label AS target_label,
       b.name AS target_name,
       b.file_path AS target_file,
       json_extract(e.properties, '$.line') AS line,
       json_extract(e.properties, '$.strategy') AS strategy
FROM edges e
JOIN nodes a ON a.id = e.source_id
JOIN nodes b ON b.id = e.target_id
WHERE e.type = 'CALLS'
ORDER BY a.file_path, line, a.name, b.name
"""


def source_key(label: str, name: str, file_path: str | None) -> str:
    # Folder/File/Module source: use the file name. Functions/methods: name.
    if label == "Module" and file_path:
        return Path(file_path).name
    return name


def rows(db: str):
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    try:
        return [dict(row) for row in con.execute(QUERY)]
    finally:
        con.close()


def score(actual: set[tuple[str, str]], expected: set[tuple[str, str]]):
    tp = len(actual & expected)
    fp = len(actual - expected)
    fn = len(expected - actual)
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    return {
        "tp": tp,
        "fp": fp,
        "fn": fn,
        "precision": round(precision, 4),
        "recall": round(recall, 4),
        "f1": round(f1, 4),
        "false_positives": sorted(actual - expected),
        "false_negatives": sorted(expected - actual),
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("cbm_db")
    ap.add_argument("scip_db")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    report = {}
    for label, db in (("cbm", args.cbm_db), ("scip", args.scip_db)):
        data = rows(db)
        function_actual = {
            (source_key(r["source_label"], r["source_name"], r["source_file"]), r["target_name"])
            for r in data
            if r["source_label"] in ("Function", "Method")
        }
        module_actual = {
            (source_key(r["source_label"], r["source_name"], r["source_file"]), r["target_name"])
            for r in data
            if r["source_label"] == "Module"
        }
        report[label] = {
            "function_calls": score(function_actual, FUNCTION_GT),
            "module_calls": score(module_actual, MODULE_GT),
            "raw_edges": len(data),
            "calls": [
                {
                    "source": source_key(r["source_label"], r["source_name"], r["source_file"]),
                    "target": r["target_name"],
                    "source_label": r["source_label"],
                    "target_label": r["target_label"],
                    "line": r["line"],
                    "strategy": r["strategy"],
                }
                for r in data
            ],
        }

    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
        return

    print("A0.5 hard-fixture CALLS")
    for label in ("cbm", "scip"):
        f = report[label]["function_calls"]
        m = report[label]["module_calls"]
        print(
            f"\n{label}: function TP={f['tp']} FP={f['fp']} FN={f['fn']} "
            f"P={f['precision']:.1%} R={f['recall']:.1%} F1={f['f1']:.1%}"
        )
        if f["false_positives"]:
            print("  FP:", ", ".join(f"{a} -> {b}" for a, b in f["false_positives"]))
        if f["false_negatives"]:
            print("  FN:", ", ".join(f"{a} -> {b}" for a, b in f["false_negatives"]))
        print(f"  module edge: TP={m['tp']} FP={m['fp']} FN={m['fn']}")


if __name__ == "__main__":
    main()
