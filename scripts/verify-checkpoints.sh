#!/usr/bin/env bash
# verify-checkpoints.sh — 校验 git-checkpoints.jsonl 与 git 历史是否一致
#
# 检查项：
#   1. 每条 commit 在仓库中存在（无孤儿）
#   2. short 是 commit 的前缀
#   3. at 时间单调不减
#   4. 必填字段齐全
#
# 用法：scripts/verify-checkpoints.sh [jsonl路径，默认 git-checkpoints.jsonl]
set -uo pipefail

JSONL="${1:-git-checkpoints.jsonl}"
[[ -f "$JSONL" ]] || { echo "找不到 $JSONL" >&2; exit 1; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "当前目录不是 git 仓库" >&2; exit 1; }

python3 - "$JSONL" << 'PY'
import json, subprocess, sys, datetime

path = sys.argv[1]
rows, errors = [], []
with open(path, encoding="utf-8") as f:
    for lineno, line in enumerate(f, 1):
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as e:
            errors.append(f"第 {lineno} 行不是合法 JSON: {e}")
            continue
        rows.append((lineno, row))

REQUIRED = ["commit", "short", "kind", "at", "summary", "files", "insertions", "deletions"]
for lineno, row in rows:
    for key in REQUIRED:
        if key not in row:
            errors.append(f"第 {lineno} 行缺字段 {key}")
    sha = row.get("commit", "")
    if sha:
        ok = subprocess.run(["git", "cat-file", "-e", f"{sha}^{{commit}}"],
                            capture_output=True).returncode == 0
        if not ok:
            errors.append(f"第 {lineno} 行孤儿记录：提交不存在 {sha[:12]}")
        elif not sha.startswith(row.get("short", "")):
            errors.append(f"第 {lineno} 行 short 与前缀不符：{row.get('short')} vs {sha[:12]}")

last = None
for lineno, row in rows:
    at = row.get("at")
    if not at:
        continue
    try:
        dt = datetime.datetime.fromisoformat(at.replace("Z", "+00:00"))
    except ValueError:
        errors.append(f"第 {lineno} 行 at 不是 ISO8601: {at}")
        continue
    if last and dt < last:
        errors.append(f"第 {lineno} 行时间倒退：{at}")
    last = dt

print(f"记录 {len(rows)} 条")
if errors:
    print(f"❌ {len(errors)} 个问题：")
    for e in errors:
        print("  -", e)
    sys.exit(1)
print("✅ 全部一致：无孤儿、前缀正确、时间单调")
PY
