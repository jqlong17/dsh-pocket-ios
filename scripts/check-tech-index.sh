#!/usr/bin/env bash
# check-tech-index.sh — 校验 TECH_INDEX.md 里每条「文件 · 符号」是否还存在
#
# 为什么需要它：索引的价值全在「准」。符号改名、文件搬走之后如果没人发现，
# 下一个人（或 AI）照着索引去找会扑空，然后凭直觉猜——那正是 2026-11-22
# 「本地图片不能显示」这个错误结论的成因。
#
# 用法：./scripts/check-tech-index.sh [索引文件]
# 退出码 1 表示有失效条目。
set -uo pipefail

INDEX="${1:-TECH_INDEX.md}"

if [[ ! -f "$INDEX" ]]; then
  echo "找不到 $INDEX"
  exit 2
fi

python3 - "$INDEX" << 'PY'
import os
import re
import sys

index_path = sys.argv[1]
root = os.path.dirname(os.path.abspath(index_path))
text = open(index_path, encoding='utf-8').read()

# 匹配：`path/to/File.swift` · `Symbol`
# 也允许没有反引号的写法（防止误报）
pattern = re.compile(r'`([A-Za-z0-9_./\-]+\.(?:swift|js|md|sh|py))`\s*·\s*`([^`]+)`')

entries = pattern.findall(text)
problems = []

for rel, symbol in entries:
    full = os.path.join(root, rel)
    if not os.path.isfile(full):
        problems.append((rel, symbol, '文件不存在'))
        continue
    try:
        body = open(full, encoding='utf-8', errors='ignore').read()
    except OSError as exc:
        problems.append((rel, symbol, f'读不了：{exc}'))
        continue
    # 符号可能是「类型」「方法」或「属性」，统一做子串匹配
    if symbol not in body:
        problems.append((rel, symbol, '符号找不到'))

print(f'  索引条目：{len(entries)} 条')
if not problems:
    print('  ✅ 全部有效')
    sys.exit(0)

print(f'  ❌ {len(problems)} 条失效：')
for rel, symbol, why in problems:
    print(f'   · {rel} · {symbol} — {why}')
sys.exit(1)
PY
