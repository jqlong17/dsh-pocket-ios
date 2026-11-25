#!/usr/bin/env bash
#
# 提交/部署前的统一检查。任何一步失败就停下。
#
# 为什么需要：2026-11-25 出了一次「用了没 import」的错——语法检查通过、
# 单元测试全绿，但真跑起来 ReferenceError，面板直接白屏/报错。
# 这类问题只有把检查固定成流程的一部分才能不再复发。
#
# 用法：
#   ./scripts/preflight.sh           只跑静态与单元测试
#   ./scripts/preflight.sh --live    额外检查本机真实状态（serve 端口一致性）
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

LIVE=0
[ "${1:-}" = "--live" ] && LIVE=1

pass=0; fail=0
step() { printf '\n▸ %s\n' "$*"; }
ok()   { printf '  ✅ %s\n' "$*"; pass=$((pass+1)); }
bad()  { printf '  ❌ %s\n' "$*"; fail=$((fail+1)); }

# ── 1. 插件：语法 + 单元测试（含接线与面板静态检查）──────────────
# ── 0. 脚本自身检查（先跑，避免检查脚本自己就是坏的）────────────
step 'Shell 脚本：语法'
shell_bad=0
for f in scripts/*.sh; do
  bash -n "$f" 2>/dev/null || { bad "语法错误：$f"; shell_bad=1; }
done
[ "$shell_bad" -eq 0 ] && ok '所有 shell 脚本语法通过'

step 'Shell 脚本：变量紧邻多字节字符（曾一天踩三次）'
if python3 scripts/check-shell-vars.py >/tmp/preflight-shellvars.log 2>&1; then
  ok '没有变量紧邻多字节字符的问题'
else
  bad '存在「$VAR 紧跟中文/全角标点」的写法'
  tail -6 /tmp/preflight-shellvars.log | sed 's/^/      /'
fi

step 'iOS：本地化棘轮（不许新增未翻译文案）'
if python3 scripts/check-l10n.py >/tmp/preflight-l10n.log 2>&1; then
  ok "$(grep -m1 '字面量' /tmp/preflight-l10n.log | sed 's/^ *//')"
else
  bad '新增了没有英文映射的文案'
  tail -6 /tmp/preflight-l10n.log | sed 's/^/      /'
fi

step '插件：语法检查'
for f in plugin/lib/*.js plugin/client/client.js; do
  if node --check "$f" >/dev/null 2>&1; then :; else bad "语法错误：$f"; fi
done
[ "$fail" -eq 0 ] && ok '所有 JS 文件语法通过'

step '插件：单元测试'
if (cd plugin && npm test >/tmp/preflight-npm.log 2>&1); then
  RESULT=$(grep -E '^# (pass|fail)' /tmp/preflight-npm.log | tr '\n' ' ')
  ok "npm test 通过（${RESULT}）"
else
  bad "npm test 失败，详情：/tmp/preflight-npm.log"
  grep -E '^not ok' /tmp/preflight-npm.log | head -5 | sed 's/^/      /'
fi

# ── 2. iOS：单元测试 + 架构检查 ───────────────────────────────────
step 'iOS：DSHKit 测试'
if (cd DSHKit && swift test >/tmp/preflight-swift.log 2>&1); then
  ok 'swift test 通过'
else
  bad 'swift test 失败，详情：/tmp/preflight-swift.log'
fi

step 'iOS：架构检查'
if ./scripts/check-architecture.sh >/tmp/preflight-arch.log 2>&1; then
  ok 'check-architecture 通过'
else
  bad 'check-architecture 失败'
  tail -5 /tmp/preflight-arch.log | sed 's/^/      /'
fi

# ── 3. 可选：真实环境检查 ────────────────────────────────────────
if [ "$LIVE" -eq 1 ]; then
  step '真实环境：serve 端口一致性'
  if ./scripts/check-serve-port.sh; then
    ok 'serve 端口与插件端口一致'
  else
    bad 'serve 端口不一致（扫码会失败）'
  fi
fi

printf '\n结果：%d 通过 / %d 失败\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
