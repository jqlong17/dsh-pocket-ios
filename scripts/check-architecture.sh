#!/usr/bin/env bash
# check-architecture.sh — 按 fact.json 的违规清单卡架构红线
#
# 用途：可放进 CI / 提交前自检。退出码 1 表示有违规。
# 与 architecture-facts.sh 的分工：那个负责「扫出事实」，这个负责「按事实判违规」。
#
# 用法：
#   ./scripts/check-architecture.sh              # 重新扫描并检查
#   ./scripts/check-architecture.sh --facts      # 用已有 fact.json，不重扫
set -uo pipefail
FACTS="docs/architecture/fact.json"

if [[ "${1:-}" != "--facts" ]]; then
  ./scripts/architecture-facts.sh "$FACTS" >/dev/null
fi

python3 - "$FACTS" << 'PY'
import json, sys

path = sys.argv[1]
try:
    facts = json.load(open(path, encoding="utf-8"))
except FileNotFoundError:
    print(f"找不到 {path}，先跑 scripts/architecture-facts.sh")
    sys.exit(2)

violations = facts.get("violations", [])
if not violations:
    print(f"✅ 架构检查通过（{facts.get('commit')}，{len(facts.get('modules', []))} 个文件）")
    sys.exit(0)

by_rule = {}
for v in violations:
    by_rule.setdefault(v["rule"], []).append(v)

print(f"❌ {len(violations)} 处违规（{facts.get('commit')}）：")
for rule, items in sorted(by_rule.items()):
    print(f"\n[{rule}] {len(items)} 处")
    for item in items:
        print(f"  - {item['file']} — {item['detail']}")
print("\n处置：新增的违规必须当次修掉；存量违规按 spec 逐步还债（不要一次性大改）。")
sys.exit(1)
PY
