#!/usr/bin/env bash
# 本机跑对话页 UI 回归（Demo 模式，无需电脑/网络）。
# 用法：scripts/run-ui-tests.sh [模拟器 UDID]
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${1:-$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next(dev["udid"] for runtime in d.values() for dev in runtime if dev.get("state")=="Booted"), end=""))}')"
if [[ -z "${DEVICE}" ]]; then
  echo "没有已启动的模拟器，请先启动一个 iPhone 模拟器。" >&2
  exit 1
fi
DERIVED="${DERIVED_DATA:-/tmp/dsh-pocket-ios-sim-derived}"

echo "▶ build-for-testing (device=$DEVICE)"
xcodebuild build-for-testing \
  -project DSHPocket.xcodeproj -scheme DSHPocket \
  -destination "id=$DEVICE" -derivedDataPath "$DERIVED" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO

echo "▶ test-without-building"
xcodebuild test-without-building \
  -project DSHPocket.xcodeproj -scheme DSHPocket \
  -destination "id=$DEVICE" -derivedDataPath "$DERIVED" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO
