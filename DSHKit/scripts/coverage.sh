#!/usr/bin/env bash
# DSHKit 行覆盖率门槛（默认 85%）。
set -euo pipefail
cd "$(dirname "$0")/.."
MIN="${1:-85}"
swift test --enable-code-coverage >/dev/null
PROF=$(find .build -name default.profdata | head -1)
BIN=$(find .build -name 'DSHKitTests' -type f -path '*Contents/MacOS*' | head -1)
xcrun llvm-cov report "$BIN" -instr-profile="$PROF" \
  -ignore-filename-regex='\.build|Tests|Fixtures' > /tmp/dshkit-coverage.txt
TOTAL=$(grep -E '^TOTAL' /tmp/dshkit-coverage.txt | awk '{print $10}' | tr -d '%')
echo "DSHKit line coverage: ${TOTAL}% (min ${MIN}%)"
tail -12 /tmp/dshkit-coverage.txt
awk -v t="$TOTAL" -v m="$MIN" 'BEGIN { exit (t+0 >= m+0) ? 0 : 1 }' || {
  echo "FAIL: coverage ${TOTAL}% < ${MIN}%"; exit 1;
}
echo "PASS"
