#!/usr/bin/env bash
#
# UI 测试门禁：真跑一遍 DSHPocketUITests。
#
# 为什么单独一个脚本：UI 测试要起模拟器、跑 3-5 分钟，不适合挂在每次 commit 的
# preflight 里；但**发版必须过**（2026-11-25 决策：UI 测试提为阻断门禁）。
# 由 `./scripts/preflight.sh --release` 调用。
#
# 用法：
#   ./scripts/check-ui-tests.sh                 # 用默认模拟器
#   DSH_UI_SIM=<udid> ./scripts/check-ui-tests.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

SIM="${DSH_UI_SIM:-2BD221E6-CFAA-4E90-8BEB-E7392ACCCB19}"
LOG=/tmp/ui-gate.log
echo "  模拟器: $SIM"

# 模拟器没启动就启动（已启动时 bootstatus 直接返回）。
xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1 || true

timeout 1800 xcodebuild test \
  -project DSHPocket.xcodeproj \
  -scheme DSHPocket \
  -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath /tmp/dd-ui \
  -only-testing:DSHPocketUITests \
  CODE_SIGNING_ALLOWED=NO \
  > "$LOG" 2>&1

code=$?
# 注意：grep -c 在 0 匹配时退出码为 1，`|| echo 0` 会再补一行 0，
# 变成 "0\n0" 让 [: integer 报错。所以只取输出，不兜底。
passed=$(grep -c "Test Case .*passed" "$LOG" 2>/dev/null || true)
failed=$(grep -c "Test Case .*failed" "$LOG" 2>/dev/null || true)
passed=${passed:-0}; failed=${failed:-0}
skipped=$(grep -c "Test Case .*skipped" "$LOG" 2>/dev/null || true)
skipped=${skipped:-0}
echo "  用例: 通过 ${passed} · 失败 ${failed} · 跳过 ${skipped}（日志 ${LOG}）"

# 跳过不算失败，但必须可见：跳过的用例等于没测，别让门禁“假绿”。
[ "${skipped:-0}" -gt 0 ] && echo "  ⚠️  有 ${skipped} 条用例被跳过，等于没有覆盖"

if [ "$code" -eq 0 ] && [ "$failed" -eq 0 ] && grep -q "TEST SUCCEEDED" "$LOG"; then
  echo "  ✅ UI 测试通过"
  exit 0
fi
echo "  ❌ UI 测试失败（发版门禁不通过）"
grep -E "Test Case .*failed|error:" "$LOG" | head -8 | sed 's/^/      /'
exit 1
