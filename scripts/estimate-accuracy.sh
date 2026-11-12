#!/usr/bin/env bash
# estimate-accuracy.sh — 统计「预估 vs 实际」偏差，产出下次预估该乘的系数
#
# 为什么需要它：AI 估工时的偏差是系统性的（常见是估大 3–10 倍），
# 靠感觉修正不了，只能靠历史数据的倍率中位数来校准。
#
# 用法：scripts/estimate-accuracy.sh [jsonl路径，默认 git-checkpoints.jsonl]
set -uo pipefail

JSONL="${1:-git-checkpoints.jsonl}"
[[ -f "$JSONL" ]] || { echo "找不到 $JSONL（先打几个检查点再来）" >&2; exit 1; }

python3 - "$JSONL" << 'PY'
import json, sys, statistics

path = sys.argv[1]
rows = []
with open(path, encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue

pairs = []
pending_estimate = None
pending_spec = None
for row in rows:
    if row.get("kind") == "baseline":
        pending_estimate = row.get("estimate_minutes")
        pending_spec = row.get("spec") or row.get("summary")
    elif row.get("kind") == "result":
        actual = row.get("actual_minutes")
        estimate = row.get("estimate_minutes") or pending_estimate
        if actual is not None and estimate:
            pairs.append((pending_spec or row.get("spec") or "-", estimate, actual, actual / estimate))
        pending_estimate = None
        pending_spec = None

if not pairs:
    print("还没有同时记录了预估与实际的数据（baseline 要带 --estimate，result 会自动算实际）。")
    sys.exit(0)

print(f"{'主题':44} {'预估(分)':>8} {'实际(分)':>8} {'倍率':>6}")
print("-" * 72)
for spec, estimate, actual, ratio in pairs:
    print(f"{str(spec)[:44]:44} {estimate:8g} {actual:8g} {ratio:6.2f}")

ratios = [p[3] for p in pairs]
median = statistics.median(ratios)
print("-" * 72)
print(f"样本 {len(pairs)} 个，倍率中位数 {median:.2f}×")
if median < 0.5:
    print(f"→ 系统性高估：下次把预估 × {median:.2f}（例如估 60 分钟就写 {max(1, round(60*median))} 分钟）")
elif median > 2:
    print(f"→ 系统性低估：下次把预估 × {median:.2f}")
else:
    print("→ 预估基本准确，保持当前口径")
PY
