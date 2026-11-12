#!/usr/bin/env bash
# record-checkpoint.sh — 把一次 git 提交追加到项目的 git-checkpoints.jsonl
#
# 用法（在项目仓库根目录执行，先提交主改动再记录）：
#   scripts/record-checkpoint.sh result --spec spec/10-image-pipeline.md --note "上限 9 张/50MB"
#   scripts/record-checkpoint.sh baseline --spec spec/11-x.md --estimate 90   # 预估 90 分钟
#   scripts/record-checkpoint.sh result --spec spec/11-x.md --actual-minutes 35  # 实际 35 分钟
#   不传 --actual-minutes 时，自动按「最近一条 baseline 的时间 → 本次提交时间」计算实际耗时。
#   scripts/record-checkpoint.sh baseline --note "开始做会话进入收口"
#   scripts/record-checkpoint.sh result --commit <sha>   # 指定提交（默认 HEAD）
#
# 为什么分两步：git 的 sha 由内容决定，提交时才知道；
# 要先提交拿到固定 sha，再写入记录，两边才永远一致。绝不要 amend。
set -euo pipefail

JSONL="git-checkpoints.jsonl"
KIND="${1:-}"; shift || true
SHA=""; SPEC=""; NOTE=""; TESTS=""; VERIFY=""; RISK=""
ESTIMATE=""; ACTUAL_START=""; ACTUAL_MINUTES=""

if [[ "$KIND" != "baseline" && "$KIND" != "result" && "$KIND" != "correction" && "$KIND" != "rewrite" ]]; then
  echo "用法: $0 <baseline|result|correction|rewrite> [--commit sha] [--spec path] [--estimate 分钟] [--actual-start ISO8601] [--actual-minutes 分钟] [--tests 文本] [--verify 文本] [--risk 文本] [--note 文本]" >&2
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
    --estimate) ESTIMATE="${2:-}"; shift 2 ;;
    --actual-start) ACTUAL_START="${2:-}"; shift 2 ;;
    --actual-minutes) ACTUAL_MINUTES="${2:-}"; shift 2 ;;
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
# 提交时间是「代码状态时刻」，但记录时刻可能更晚（先提交、后补记）。
# 若比上一条记录还早，就把 at 改成当前时间，避免 verify 报「时间倒退」。
LAST_AT="$(tail -1 git-checkpoints.jsonl 2>/dev/null | python3 -c "import json,sys
try: print(json.load(sys.stdin).get('at') or '')
except Exception: print('')" 2>/dev/null)"
if [ -n "$LAST_AT" ] && [[ "$AT" < "$LAST_AT" ]]; then
  AT="$(python3 -c "import datetime; print(datetime.datetime.now().astimezone().isoformat(timespec='seconds'))")"
fi
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
python3 - "$JSONL" "$FULL" "$SHORT" "$KIND" "$AT" "$SUMMARY" "$SPEC" "$TESTS" "$VERIFY" "$RISK" "$NOTE" "$FILES" "$INS" "$DEL" "$ESTIMATE" "$ACTUAL_START" "$ACTUAL_MINUTES" << 'PY'
import json, sys, os, datetime
(path, full, short, kind, at, summary, spec, tests, verify, risk, note,
 files, ins, dele, estimate_raw, actual_start, actual_min_raw) = sys.argv[1:18]
def parse_minutes(raw):
    if raw in ("", None):
        return None
    try:
        return float(raw)
    except ValueError:
        return None

def last_baseline(path):
    """最近一条 baseline 的 (时间, 预估分钟)：分别作「开始执行」锚点与预估继承。"""
    at = None
    est = None
    if not os.path.exists(path):
        return at, est
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except json.JSONDecodeError:
                continue
            if r.get("kind") == "baseline":
                at = r.get("at")
                est = r.get("estimate_minutes")
    return at, est

base_at, base_estimate = last_baseline(path)

estimate = parse_minutes(estimate_raw)
# result 行继承 baseline 的预估，保证每行自包含（查询/统计不必跨行配对）。
if estimate is None and kind == "result":
    estimate = base_estimate
actual = parse_minutes(actual_min_raw)
# 没显式给实际耗时就自动算：从最近 baseline（或指定起点）到本次提交。
if actual is None and kind == "result":
    anchor = actual_start or base_at
    if anchor:
        try:
            start_dt = datetime.datetime.fromisoformat(anchor.replace("Z", "+00:00"))
            end_dt = datetime.datetime.fromisoformat(at.replace("Z", "+00:00"))
            delta = (end_dt - start_dt).total_seconds() / 60
            if delta >= 0:
                actual = round(delta, 1)
        except ValueError:
            pass

# 偏差倍率：实际 / 预估。小于 1 表示预估偏大（AI 常见）。
deviation = round(actual / estimate, 2) if (actual and estimate and estimate > 0) else None

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
    "estimate_minutes": estimate,
    "actual_minutes": actual,
    "deviation": deviation,
}
with open(path, "a", encoding="utf-8") as f:
    f.write(json.dumps(row, ensure_ascii=False) + "\n")
print(f"已追加 {kind} 检查点: {short} — {summary}")
if estimate is not None:
    print(f"  预估 {estimate:g} 分钟", end="")
    if actual is not None:
        print(f"，实际 {actual:g} 分钟，偏差 {deviation}×" if deviation else f"，实际 {actual:g} 分钟")
    else:
        print()
PY

cat <<EOF

下一步：把记录一起提交（保持记录与代码在同一仓库）
  git add $JSONL && git commit -m "chore: 记录检查点 ${SHORT}"
EOF
