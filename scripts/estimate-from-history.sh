#!/usr/bin/env bash
# 按「改动类型」查历史实测中位数，作为预估依据。
#
# 为什么需要它：直觉估总量会系统性高估 1.6 倍（49 个样本，倍率中位数稳定在 0.61）。
# 数据表明成本驱动不是行数，而是「需要判断的地方」——机械搬迁 1.6 分/百行，
# 逐点重构 25–67 分/百行。所以预估应当查同类历史，而不是凭感觉。
#
# 用法：./scripts/estimate-from-history.sh [类型关键字]
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - "$@" << 'PY'
import json, statistics, sys, collections

KEYWORD = sys.argv[1] if len(sys.argv) > 1 else ""

def kind_of(summary: str) -> str:
    s = summary.lower()
    if "拆成" in summary or "搬到" in summary or "拆出" in summary: return "文件拆分/搬迁"
    if "抽出" in summary or "抽成" in summary: return "抽类型+策略"
    if "直达" in summary or "直读" in summary or "替换" in summary or "统一" in summary: return "逐点重构"
    if "fix" in s: return "缺陷修复"
    if "docs" in s or "spec" in s: return "文档/spec"
    if "feat" in s: return "新功能"
    return "其它"

rows = collections.defaultdict(list)
for line in open("git-checkpoints.jsonl", encoding="utf-8"):
    r = json.loads(line)
    if r.get("kind") != "result":
        continue
    e, a = r.get("estimate_minutes"), r.get("actual_minutes")
    if not e or not a:
        continue
    rows[kind_of(r.get("summary") or "")].append((e, a, r.get("summary") or ""))

print(f"{'类型':<12}{'n':>3}{'预估中位':>9}{'实际中位':>9}{'单次实际':>9}")
print("-" * 46)
for k, v in sorted(rows.items(), key=lambda x: -len(x[1])):
    if KEYWORD and KEYWORD not in k:
        continue
    est = statistics.median([x[0] for x in v])
    act = statistics.median([x[1] for x in v])
    print(f"{k:<12}{len(v):>3}{est:>9.0f}{act:>9.0f}{act:>9.0f}")

print()
print("用法：预估 = 同类「实际中位」，而不是凭直觉；没有同类历史时，")
print("      拆成最小验证单元（每处调用点 / 每个新文件 / 每轮编译）再逐项累加。")
PY
