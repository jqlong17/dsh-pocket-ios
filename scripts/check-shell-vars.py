#!/usr/bin/env python3
"""检查 shell 脚本里「变量紧邻多字节字符」的写法。

为什么：`$VAR` 后面直接跟中文或全角标点（比如 `$RESULT）`）时，bash 会把
多字节字符算进变量名，报 `RESULT�: unbound variable` —— 2026-11-25 一天里
踩了三次（脚本、测试、部署脚本各一次）。必须写成 `${VAR}）`。

用法：python3 scripts/check-shell-vars.py [文件...]（默认扫仓库里的 *.sh）
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PATTERN = re.compile(r'\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7f]')


def files_from_args(argv):
    if argv:
        return [Path(a) for a in argv]
    out = subprocess.run(['git', 'ls-files', '*.sh'], cwd=ROOT, capture_output=True, text=True)
    return [ROOT / line for line in out.stdout.splitlines() if line.strip()]


def main(argv):
    problems = 0
    for path in files_from_args(argv):
        if not path.exists():
            continue
        for lineno, line in enumerate(path.read_text(encoding='utf-8', errors='ignore').splitlines(), 1):
            if line.lstrip().startswith('#'):
                continue
            for match in PATTERN.finditer(line):
                problems += 1
                rel = path.relative_to(ROOT) if path.is_relative_to(ROOT) else path
                print(f'  {rel}:{lineno}: {match.group(0)!r} → 改成 ${{...}} 形式')
    if problems:
        print(f'\n❌ 发现 {problems} 处「变量紧邻多字节字符」')
        return 1
    print('  ✅ 没有「变量紧邻多字节字符」的问题')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
