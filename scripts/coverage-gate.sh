#!/usr/bin/env bash
# 覆盖率门槛：解析 xccov JSON，按 target/目录过滤后检查行覆盖率。
# 用法: coverage-gate.sh <coverage.json> <minPercent> [target-or-path-keyword]
set -euo pipefail

JSON="${1:?usage: coverage-gate.sh <coverage.json> <minPercent> [keyword]}"
MIN="${2:-85}"
KEYWORD="${3:-}"

python3 - "$JSON" "$MIN" "$KEYWORD" <<'PY'
import json, sys

path, minimum, keyword = sys.argv[1], float(sys.argv[2]), sys.argv[3]
data = json.load(open(path))

def walk(node, out):
    name = node.get("name", "")
    targets = node.get("targets")
    if targets:
        for t in targets:
            walk(t, out)
    else:
        out.append(node)

targets = []
walk(data, targets)
if keyword:
    targets = [t for t in targets if keyword.lower() in t.get("name", "").lower()]

if not targets:
    print(f"FAIL: no targets matched keyword={keyword!r}")
    sys.exit(1)

failed = False
for t in targets:
    pct = float(t.get("lineCoverage", 0)) * 100
    status = "PASS" if pct >= minimum else "FAIL"
    print(f"{status} {t.get('name')}: {pct:.1f}% (min {minimum:.0f}%)")
    if pct < minimum:
        failed = True

sys.exit(1 if failed else 0)
PY
