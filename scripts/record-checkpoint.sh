#!/usr/bin/env bash
# record-checkpoint.sh — 把一次 git 提交追加到项目的 git-checkpoints.jsonl
#
# 用法（在项目仓库根目录执行，先提交主改动再记录）：
#   scripts/record-checkpoint.sh result --spec spec/10-image-pipeline.md --note "上限 9 张/50MB"
#   scripts/record-checkpoint.sh baseline --note "开始做会话进入收口"
#   scripts/record-checkpoint.sh result --commit <sha>   # 指定提交（默认 HEAD）
#
# 为什么分两步：git 的 sha 由内容决定，提交时才知道；
# 要先提交拿到固定 sha，再写入记录，两边才永远一致。绝不要 amend。
set -euo pipefail

JSONL="git-checkpoints.jsonl"
KIND="${1:-}"; shift || true
SHA=""; SPEC=""; NOTE=""; TESTS=""; VERIFY=""; RISK=""

if [[ "$KIND" != "baseline" && "$KIND" != "result" && "$KIND" != "correction" && "$KIND" != "rewrite" ]]; then
  echo "用法: $0 <baseline|result|correction|rewrite> [--commit sha] [--spec path] [--tests 文本] [--verify 文本] [--risk 文本] [--note 文本]" >&2
  exit 2
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --commit) SHA="${2:-}"; shift 2 ;;
    --spec)   SPEC="${2:-}"; shift 2 ;;
    --tests)  TESTS="${2:-}"; shift 2 ;;
    --verify) VERIFY="${2:-}"; shift 2 ;;
    --risk)   RISK="${2:-}"; shift 2 ;;
    --note)   NOTE="${2:-}"; shift 2 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

git rev-parse --git-dir >/dev/null 2>&1 || { echo "当前目录不是 git 仓库" >&2; exit 1; }
[[ -z "$SHA" ]] && SHA="$(git rev-parse HEAD)"

# 校验 sha 存在，避免记录指向不存在的提交
git cat-file -e "${SHA}^{commit}" 2>/dev/null || { echo "提交不存在: $SHA" >&2; exit 1; }

FULL="$(git rev-parse "$SHA")"
# 固定 7 位短 sha（macOS 的 BSD sed/git 行为不同，统一用 --short=7 避免歧义）
SHORT="$(git rev-parse --short=7 "$SHA")"
AT="$(git show -s --format=%cI "$SHA")"
SUMMARY="$(git show -s --format=%s "$SHA")"

# 改动规模：与父提交比较；根提交与「空树」比较，两条路径都能统计。
# 注意用的是 BSD sed（macOS），必须 -E 才能用 files?/insertions? 这类量词。
EMPTY_TREE=4b825dc642cb6eb9a060e54bf8d69288fbee4904
if git rev-parse "$SHA^" >/dev/null 2>&1; then
  BASE="$SHA^"
else
  BASE="$EMPTY_TREE"
fi
STAT="$(git diff --shortstat "$BASE" "$SHA")"
FILES="$(sed -E -n 's/^ *([0-9]+) files? changed.*/\1/p' <<<"$STAT" | head -1)"; FILES="${FILES:-0}"
INS="$(sed -E -n 's/.* ([0-9]+) insertions?.*/\1/p' <<<"$STAT" | head -1)"; INS="${INS:-0}"
DEL="$(sed -E -n 's/.* ([0-9]+) deletions?.*/\1/p' <<<"$STAT" | head -1)"; DEL="${DEL:-0}"

# 用 python 生成合法 JSON（避免手拼引号）
python3 - "$JSONL" "$FULL" "$SHORT" "$KIND" "$AT" "$SUMMARY" "$SPEC" "$TESTS" "$VERIFY" "$RISK" "$NOTE" "$FILES" "$INS" "$DEL" << 'PY'
import json, sys, os
path, full, short, kind, at, summary, spec, tests, verify, risk, note, files, ins, dele = sys.argv[1:15]
row = {
    "commit": full,
    "short": short,
    "kind": kind,
    "at": at,
    "summary": summary,
    "spec": spec or None,
    "files": int(files),
    "insertions": int(ins),
    "deletions": int(dele),
    "tests": tests or None,
    "verify": verify or None,
    "risk": risk or None,
    "note": note or None,
}
with open(path, "a", encoding="utf-8") as f:
    f.write(json.dumps(row, ensure_ascii=False) + "\n")
print(f"已追加 {kind} 检查点: {short} — {summary}")
PY

cat <<EOF

下一步：把记录一起提交（保持记录与代码在同一仓库）
  git add $JSONL && git commit -m "chore: 记录检查点 ${SHORT}"
EOF
