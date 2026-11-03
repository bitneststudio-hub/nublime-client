#!/usr/bin/env python3
"""Provenance scanner — three baselines x three checks.

Used by the WildLime clean-room process (see docs/provenance/README.md).

Checks per target file:
  A. file-level normalized similarity against each baseline (threshold 0.35)
  B. longest shared token window against each baseline (flag >= 50 tokens)
  C. hits of "forbidden identifiers" (names copied from the baseline)

Usage:
  python3 scan.py --target <dir> --baseline <name>=<dir> [--baseline ...] \
                  --forbidden-from <dir> --out <report.json> [--markdown <report.md>]

Exit code 0 when every file passes, 1 when any file breaks a threshold.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import difflib
from collections import defaultdict

CODE_EXT = (".dart", ".kt", ".java", ".swift", ".cs", ".cpp", ".h")

# --- normalization -----------------------------------------------------------

_COMMENT_BLOCK = re.compile(r"/\*.*?\*/", re.S)
_COMMENT_LINE = re.compile(r"//[^\n]*")
_WS = re.compile(r"\s+")
_TOKEN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*|[{}()\[\];,.<>=+\-*/%!&|?:]|\d+")


def read(path: str) -> str:
    with open(path, encoding="utf-8", errors="ignore") as fh:
        return fh.read()


def normalize(text: str) -> str:
    text = _COMMENT_BLOCK.sub(" ", text)
    text = _COMMENT_LINE.sub(" ", text)
    return _WS.sub(" ", text).strip()


def tokens(text: str) -> list[str]:
    return _TOKEN.findall(normalize(text))


def shingles(toks: list[str], size: int) -> set[tuple]:
    if len(toks) < size:
        return {tuple(toks)} if toks else set()
    return {tuple(toks[i:i + size]) for i in range(len(toks) - size + 1)}


# --- loading -----------------------------------------------------------------

def walk(root: str) -> dict[str, str]:
    out = {}
    for base, _dirs, files in os.walk(root):
        for name in files:
            if name.endswith(CODE_EXT):
                path = os.path.join(base, name)
                out[os.path.relpath(path, root)] = path
    return out


GENERIC = set("""
the and for with from that this not are was were you your our its has have had
self true false null None null void var final const static class extends implements
import export return if else for while switch case break continue default new
async await yield try catch finally throw throws throwException
get set this super override late required factory operator external abstract
extension mixin typedef enum Future FutureOr Stream List Map Set Iterable String int
double bool dynamic Object Type Function void StatefulWidget StatelessWidget Widget
BuildContext State BuildKey Key EdgeInsets Colors Color TextStyle Text SizedBox Row
Column Container Padding Center Align Expanded Flexible Stack Positioned ListView
Scaffold AppBar TextButton IconButton ElevatedButton TextField Theme ThemeData
Provider ConsumerWidget ConsumerState ConsumerStatefulWidget WidgetRef Ref
ref watch read listen watchAll state notifier Notifier AsyncNotifier build
initState dispose context widget
""".split())


def collect_identifiers(root: str, skip: set[str]) -> dict[str, set[str]]:
    """identifier -> set of files it appears in (relative paths)."""
    idx: dict[str, set[str]] = defaultdict(set)
    for rel, path in walk(root).items():
        for ident in set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", read(path))):
            if len(ident) >= 4 and ident not in skip:
                idx[ident].add(rel)
    return idx


def build_forbidden(baseline_dir: str, generic_repos: list[str]) -> set[str]:
    """Identifiers unique-ish to the baseline: in baseline, absent from generic SDKs."""
    generic: set[str] = set(GENERIC)
    for repo in generic_repos:
        if not os.path.isdir(repo):
            continue
        for _rel, path in walk(repo).items():
            generic.update(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", read(path)))
    idx = collect_identifiers(baseline_dir, generic)
    # keep identifiers that look project-specific
    return {i for i in idx if not i.isupper() and len(i) >= 6}


# --- scanning ----------------------------------------------------------------

def scan(target: str, baselines: dict[str, str], forbidden: set[str],
         sim_threshold: float, window: int) -> list[dict]:
    K = 8  # shingle size for the fast similarity metric
    base: dict[str, dict[str, dict]] = {}
    for name, root in baselines.items():
        files: dict[str, dict] = {}
        for rel, path in walk(root).items():
            raw = read(path)
            toks = tokens(raw)
            files[rel] = {
                "norm": normalize(raw),
                "toks": toks,
                "k": shingles(toks, K),
                "w": shingles(toks, window),
            }
        base[name] = files

    results = []
    for rel, path in walk(target).items():
        raw = read(path)
        norm = normalize(raw)
        toks = tokens(raw)
        kset = shingles(toks, K)
        wset = shingles(toks, window)
        entry = {"file": rel, "checks": {}}
        worst, longest = 0.0, 0
        for name, files in base.items():
            same_name = [k for k in files if os.path.basename(k) == os.path.basename(rel)]
            candidates = same_name or [
                k for k in files
                if abs(len(files[k]["norm"]) - len(norm)) < 0.4 * max(len(norm), 1)
            ][:15]
            best_sim, best_rel = 0.0, ""
            best_window, best_window_rel = 0, ""
            for brel in candidates:
                b = files[brel]
                if not b["toks"]:
                    continue
                union = kset | b["k"]
                sim = len(kset & b["k"]) / len(union) if union else 0.0
                if sim > best_sim:
                    best_sim, best_rel = sim, brel
                if wset & b["w"]:
                    w = _longest_run(toks, b["toks"])
                    if w > best_window:
                        best_window, best_window_rel = w, brel
            entry["checks"][name] = {
                "token_similarity": round(best_sim, 3),
                "against": best_rel,
                "longest_shared_window_tokens": best_window,
                "window_against": best_window_rel,
            }
            worst = max(worst, best_sim)
            longest = max(longest, best_window)
        ident_hits = sorted(set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", raw)) & forbidden)
        entry["forbidden_identifiers"] = ident_hits[:20]
        entry["pass"] = (worst < sim_threshold and longest < window and not ident_hits)
        results.append(entry)
    return results


def _longest_run(a: list[str], b: list[str], cap: int = 400) -> int:
    """Longest common contiguous token run, found by binary search over window sizes.

    Exact enough for the gate (we only need to know whether the maximum run is
    below the threshold and roughly how big it is); O(n log n) instead of O(n*m).
    """
    if not a or not b:
        return 0
    lo, hi = 0, min(len(a), len(b), cap)
    if not (set(a) & set(b)):
        return 0
    def has(size: int) -> bool:
        if size == 0:
            return True
        return bool(shingles(a, size) & shingles(b, size))
    # exponential growth from a small floor, then binary search
    lo = 1
    while lo < hi and has(lo * 2):
        lo *= 2
    hi = min(lo, len(a), len(b), cap)
    lo = max(1, lo // 2)
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if has(mid):
            lo = mid
        else:
            hi = mid - 1
    return lo if has(lo) else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", required=True)
    ap.add_argument("--baseline", action="append", required=True,
                    help="name=dir, repeatable")
    ap.add_argument("--forbidden-from", required=True)
    ap.add_argument("--forbidden-cache", help="JSON file to cache the forbidden identifier list")
    ap.add_argument("--generic", action="append", default=[],
                    help="dirs whose identifiers are considered generic, repeatable")
    ap.add_argument("--sim-threshold", type=float, default=0.35)
    ap.add_argument("--window", type=int, default=50)
    ap.add_argument("--out", required=True)
    ap.add_argument("--markdown")
    args = ap.parse_args()

    baselines = {}
    for spec in args.baseline:
        name, _, root = spec.partition("=")
        if not root:
            ap.error(f"bad --baseline spec: {spec}")
        baselines[name] = root

    cache = args.forbidden_cache
    if cache and os.path.exists(cache):
        with open(cache, encoding="utf-8") as fh:
            forbidden = set(json.load(fh))
        print(f"forbidden identifiers loaded from cache: {len(forbidden)}")
    else:
        forbidden = build_forbidden(args.forbidden_from, args.generic)
        if cache:
            with open(cache, "w", encoding="utf-8") as fh:
                json.dump(sorted(forbidden), fh)
            print(f"forbidden identifiers written to cache: {len(forbidden)}")
    results = scan(args.target, baselines, forbidden, args.sim_threshold, args.window)

    failing = [r for r in results if not r["pass"]]
    report = {
        "target": args.target,
        "baselines": list(baselines),
        "sim_threshold": args.sim_threshold,
        "window": args.window,
        "files": len(results),
        "failing": len(failing),
        "forbidden_identifier_count": len(forbidden),
        "results": results,
    }
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=1, ensure_ascii=False)

    if args.markdown:
        with open(args.markdown, "w", encoding="utf-8") as fh:
            fh.write(f"# Provenance scan\n\n- target: `{args.target}`\n")
            fh.write(f"- baselines: {', '.join(baselines)}\n")
            fh.write(f"- files: {len(results)}, failing: {len(failing)}\n")
            fh.write(f"- thresholds: similarity < {args.sim_threshold}, shared window < {args.window} tokens\n\n")
            fh.write("| file | worst similarity | longest shared window | forbidden ids |\n|---|---|---|---|\n")
            for r in sorted(results, key=lambda x: -max(c["token_similarity"] for c in x["checks"].values()))[:60]:
                sim = max(c["token_similarity"] for c in r["checks"].values())
                win = max(c["longest_shared_window_tokens"] for c in r["checks"].values())
                ids = ", ".join(r["forbidden_identifiers"][:5])
                fh.write(f"| `{r['file']}` | {sim:.3f} | {win} | {ids} |\n")

    print(f"files={len(results)} failing={len(failing)} forbidden_ids={len(forbidden)}")
    return 0 if not failing else 1


if __name__ == "__main__":
    sys.exit(main())
