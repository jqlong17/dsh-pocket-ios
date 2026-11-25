#!/usr/bin/env python3
"""本地化棘轮：不允许**新增**未翻译的中文字面量。

背景：`L10n.t("中文")` 靠 `Localization.en` 字典查英文，查不到就直接显示中文。
2026-11-25 统计：321 条字面量里 97 条没有英文映射 —— 英文用户会看到中文。

一次性补齐工作量大，所以用「棘轮」：把现存缺口记进 baseline，
**只拦截新增的**。缺口只能减、不能增。

用法：
  python3 scripts/check-l10n.py            # 检查（新增未翻译 → 退出码 1）
  python3 scripts/check-l10n.py --update   # 把当前缺口写进 baseline（仅在补齐后使用）
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / 'DSHPocket'
LOCALIZATION = APP / 'Support' / 'Localization.swift'
BASELINE = ROOT / 'scripts' / 'l10n-baseline.txt'

LITERAL = re.compile(r'L10n\.t\("((?:[^"\\]|\\.)*)"\)')


def collect_strings():
    used = set()
    for path in APP.rglob('*.swift'):
        for match in LITERAL.finditer(path.read_text(errors='ignore')):
            used.add(match.group(1))
    return used


def collect_translations():
    src = LOCALIZATION.read_text(errors='ignore')
    # en 字典的 key 是中文；只要有 "{中文}": 就算已映射
    return {m.group(1) for m in re.finditer(r'^\s*"((?:[^"\\]|\\.)*)"\s*:', src, re.M)}


def main(argv):
    used = collect_strings()
    translated = collect_translations()
    missing = sorted(used - translated)

    if '--update' in argv:
        BASELINE.write_text('\n'.join(missing) + ('\n' if missing else ''), encoding='utf-8')
        print(f'  已写入 baseline：{len(missing)} 条')
        return 0

    baseline = set()
    if BASELINE.exists():
        baseline = {line for line in BASELINE.read_text(encoding='utf-8').splitlines() if line}

    new_missing = [m for m in missing if m not in baseline]
    fixed = [b for b in baseline if b not in missing]

    print(f'  字面量 {len(used)} 条｜已翻译 {len(used) - len(missing)} 条｜未翻译 {len(missing)} 条')
    if fixed:
        print(f'  👍 有 {len(fixed)} 条缺口已补上（可以 --update 收紧 baseline）')
    if new_missing:
        print(f'  ❌ 新增 {len(new_missing)} 条未翻译：')
        for item in new_missing[:10]:
            print(f'     - {item[:60]}')
        print('     → 在 Localization.swift 的 en 字典里补上，或改文案避免新字符串')
        return 1
    print('  ✅ 没有新增未翻译文案')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
