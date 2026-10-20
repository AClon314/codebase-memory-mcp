#!/usr/bin/env python3
"""SCIP JSON -> cbm-compatible SQLite (proof of concept, not production).

Why: codebase-memory-mcp's read side (MCP tools + UI /api/*) is just SQLite.
If we can write its schema from a SCIP index, we can reuse cbm's query/UI/MCP
without forking 700+ C files. This script proves that path on a small index.

Usage:
  python3 scip-cbm-probe.py <scip-index.json> <project> <repo-root>

Output:
  ~/.cache/codebase-memory-mcp/<project>.db   (schema v3)

Then:
  codebase-memory-mcp cli --json trace_path --function-name run \
    --project <project> --direction outbound --depth 1
  codebase-memory-mcp cli --json query_graph --project <project> \
    --query "MATCH (a:Function)-[r:CALLS]->(b:Function) RETURN a.name,b.name"

Caveats:
- QNs are probe-grade (`<project>.<path>.<name>[@line]`), not a stable identity.
- Only CALLS + file tree + CONTAINS are emitted. IMPORTS/USAGE/HTTP/etc. are not.
- `sites` is a JSON array in edge properties; cbm's current UI ignores it.
"""
from __future__ import annotations

import hashlib
import json
import os
import sqlite3
import time
from collections import defaultdict

CACHE = os.environ.get("CBM_CACHE_DIR") or os.path.expanduser("~/.cache/codebase-memory-mcp")
SCHEMA_VERSION = 3

KIND_LABEL = {
    7: "Class",
    9: "Function",   # Constructor (SCIP)
    17: "Function",
    21: "Constant",
    26: "Method",
    16: "Module",
}

DDL = """
CREATE TABLE projects (name TEXT PRIMARY KEY, indexed_at TEXT NOT NULL, root_path TEXT NOT NULL);
CREATE TABLE file_hashes (project TEXT NOT NULL REFERENCES projects(name) ON DELETE CASCADE,
  rel_path TEXT NOT NULL, sha256 TEXT NOT NULL, mtime_ns INTEGER NOT NULL DEFAULT 0,
  size INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (project, rel_path));
CREATE TABLE nodes (id INTEGER PRIMARY KEY AUTOINCREMENT, project TEXT NOT NULL REFERENCES projects(name) ON DELETE CASCADE,
  label TEXT NOT NULL, name TEXT NOT NULL, qualified_name TEXT NOT NULL, file_path TEXT DEFAULT '',
  start_line INTEGER DEFAULT 0, end_line INTEGER DEFAULT 0, properties TEXT DEFAULT '{}',
  UNIQUE(project, qualified_name));
CREATE TABLE edges (id INTEGER PRIMARY KEY AUTOINCREMENT, project TEXT NOT NULL REFERENCES projects(name) ON DELETE CASCADE,
  source_id INTEGER NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
  target_id INTEGER NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
  type TEXT NOT NULL, properties TEXT DEFAULT '{}',
  url_path_gen TEXT GENERATED ALWAYS AS (json_extract(properties,'$.url_path')),
  local_name_gen TEXT GENERATED ALWAYS AS (CASE WHEN type='IMPORTS' THEN coalesce(json_extract(properties,'$.local_name'),'') ELSE '' END),
  UNIQUE(source_id, target_id, type, local_name_gen));
CREATE INDEX idx_nodes_label ON nodes(project, label);
CREATE INDEX idx_nodes_name ON nodes(project, name);
CREATE INDEX idx_nodes_file ON nodes(project, file_path);
CREATE INDEX idx_edges_source ON edges(source_id, type);
CREATE INDEX idx_edges_target ON edges(target_id, type);
CREATE INDEX idx_edges_type ON edges(project, type);
CREATE INDEX idx_edges_target_type ON edges(project, target_id, type);
CREATE INDEX idx_edges_source_type ON edges(project, source_id, type);
"""


def qn_module(project: str, path: str) -> str:
    return project + "." + path.replace("/", ".")


def main() -> None:
    import sys

    scip_path, project, root = sys.argv[1], sys.argv[2], os.path.abspath(sys.argv[3])
    index = json.load(open(scip_path))
    os.makedirs(CACHE, exist_ok=True)
    db_path = os.path.join(CACHE, project + ".db")
    if os.path.exists(db_path):
        os.remove(db_path)

    db = sqlite3.connect(db_path)
    db.executescript(DDL)
    db.execute(f"PRAGMA user_version={SCHEMA_VERSION}")
    db.execute(
        "INSERT INTO projects VALUES(?,?,?)",
        (project, time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), root),
    )

    node_ids: dict[str, int] = {}
    used_qn: dict[str, int] = defaultdict(int)

    def add_node(label: str, name: str, qn: str, file_path: str, start: int, end: int, props: dict) -> int:
        if qn in node_ids:
            return node_ids[qn]
        cur = db.execute(
            "INSERT INTO nodes(project,label,name,qualified_name,file_path,start_line,end_line,properties)"
            " VALUES(?,?,?,?,?,?,?,?)",
            (project, label, name, qn, file_path, start, end, json.dumps(props, ensure_ascii=False)),
        )
        node_ids[qn] = int(cur.lastrowid)
        return node_ids[qn]

    def add_edge(src: int, dst: int, etype: str, props: dict) -> None:
        db.execute(
            "INSERT OR IGNORE INTO edges(project,source_id,target_id,type,properties) VALUES(?,?,?,?,?)",
            (project, src, dst, etype, json.dumps(props, ensure_ascii=False)),
        )

    # File tree (so /api/tree and the UI layout have containers).
    project_node = add_node("Project", project, project, "", 0, 0, {})
    folders: dict[str, int] = {"": project_node}
    for doc in index.get("documents", []):
        rel = doc["relative_path"]
        parent = ""
        for part in rel.split("/")[:-1]:
            cur = part if not parent else parent + "/" + part
            if cur not in folders:
                folders[cur] = add_node("Folder", part, qn_module(project, cur), cur, 0, 0, {})
                add_edge(folders[parent], folders[cur], "CONTAINS_FOLDER", {})
            parent = cur
        f = add_node("File", os.path.basename(rel), fn_qn(project, rel), rel, 0, 0,
                     {"extension": os.path.splitext(rel)[1]})
        add_edge(folders[parent], f, "CONTAINS_FILE", {})
        mod = add_node("Module", rel, qn_module(project, os.path.splitext(rel)[0]),
                       rel, 1, 0, {"extension": os.path.splitext(rel)[1]})
        add_edge(f, mod, "CONTAINS_FILE", {})
        full = os.path.join(root, rel)
        try:
            payload = open(full, "rb").read()
            db.execute(
                "INSERT OR REPLACE INTO file_hashes VALUES(?,?,?,?,?)",
                (project, rel, hashlib.sha256(payload).hexdigest(),
                 int(os.stat(full).st_mtime_ns), len(payload)),
            )
        except OSError:
            pass

    # Definitions.
    defs: dict[str, dict] = {}
    for doc in index.get("documents", []):
        rel = doc["relative_path"]
        meta = {s["symbol"]: s for s in doc.get("symbols", [])}
        def_line = {}
        for occ in doc.get("occurrences", []):
            if (occ.get("symbol_roles") or 0) & 1:
                def_line[occ["symbol"]] = occ["range"][0] + 1
        for sym, info in meta.items():
            label = KIND_LABEL.get(info.get("kind"))
            name = info.get("display_name")
            if not label or label == "Module" or not name or sym not in def_line:
                continue
            base_qn = qn_module(project, os.path.splitext(rel)[0]) + "." + name
            used_qn[base_qn] += 1
            qn = base_qn if used_qn[base_qn] == 1 else f"{base_qn}@{def_line[sym]}"
            node_id = add_node(label, name, qn, rel, def_line[sym], def_line[sym], {
                "scip_symbol": sym,
                "svelte": rel.endswith(".svelte"),
            })
            defs[sym] = {"qn": qn, "id": node_id, "label": label, "line": def_line[sym], "file": rel}

    # Call edges: fork indexer emits `syntax_kind=15` + `enclosing_range`.
    calls: dict[tuple[str, str], dict] = {}
    for doc in index.get("documents", []):
        rel = doc["relative_path"]
        by_line = {d["line"]: d for d in defs.values() if d["file"] == rel and d["label"] in ("Function", "Method")}
        for occ in doc.get("occurrences", []):
            if (occ.get("symbol_roles") or 0) & 1:
                continue
            callee = defs.get(occ.get("symbol"))
            enc = occ.get("enclosing_range")
            if not callee or not enc or occ.get("syntax_kind") != 15:
                continue
            caller = by_line.get(enc[0] + 1)
            module_qn = qn_module(project, os.path.splitext(rel)[0])
            caller_qn = caller["qn"] if caller else module_qn
            caller_id = caller["id"] if caller else node_ids[module_qn]
            key = (caller_qn, callee["qn"])
            call = calls.setdefault(key, {
                "src": caller_id, "dst": callee["id"], "sites": [],
                "callee": callee["qn"].rsplit(".", 1)[-1],
            })
            call["sites"].append({"file": rel, "line": occ["range"][0] + 1, "column": occ["range"][1]})

    for (_, _), c in calls.items():
        site = c["sites"][0]
        add_edge(c["src"], c["dst"], "CALLS", {
            "callee": c["callee"],
            "confidence": 1.0,
            "strategy": "scip",
            "dispatch": "static",
            "line": site["line"],
            "column": site["column"],
            "sites": c["sites"],
        })

    db.commit()
    print(f"{db_path}: nodes={len(node_ids)} calls={len(calls)}")
    db.close()


def fn_qn(project: str, rel: str) -> str:
    return qn_module(project, rel) + ".__file__"


if __name__ == "__main__":
    main()
