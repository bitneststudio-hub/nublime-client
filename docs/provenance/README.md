# Provenance tooling

`tools/provenance/scan.py` implements the clean-room gate:

- **Baselines**: upstream `v4.1.2`, upstream `HEAD`, and the legacy B/B? file set
  from our own 4.1.43 tree.
- **Checks** per file: (A) token-shingle similarity < 0.35, (B) longest shared token
  window < 50, (C) forbidden-identifier hits = 0.

Run:

```bash
python3 tools/provenance/scan.py \
  --target app/lib \
  --baseline up412=/path/to/upstream-v4.1.2/lib \
  --baseline uphead=/path/to/upstream-head/lib \
  --forbidden-from /path/to/upstream-v4.1.2/lib \
  --forbidden-cache /tmp/forbidden-ids.json \
  --out report.json --markdown report.md
```

Exit code 0 only when every file passes. `baseline-2026-11-04.*` is the report for the
legacy tree before the rewrite: it fails by design, and is kept as the "before" image.
