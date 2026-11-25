#!/bin/bash
# 构建并上传到 TestFlight。必须在 Mac 的图形会话里跑（钥匙串要解锁）。
# 用法： bash scripts/release-testflight.sh
set -euo pipefail
cd "$(dirname "$0")/.."

KEY=CKPJTSH2KX
ISSUER=04b7fa0e-8250-419f-a0f8-a849c3fed9ca
STAMP=$(date +%Y%m%d-%H%M)
ARCHIVE="/tmp/DSHPocket-$STAMP.xcarchive"
EXPORT="/tmp/dsh-export-$STAMP"

echo "== 1/3 归档 =="
xcodebuild -project DSHPocket.xcodeproj -scheme DSHPocket -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" archive | tail -5

echo "== 2/3 导出 IPA =="
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist ExportOptions.plist -exportPath "$EXPORT" | tail -5
IPA=$(ls "$EXPORT"/*.ipa | head -1)
echo "IPA: $IPA"

echo "== 3/3 上传 TestFlight =="
xcrun altool --upload-app -f "$IPA" -t ios --apiKey "$KEY" --apiIssuer "$ISSUER" | tail -8
echo "完成。到 App Store Connect → TestFlight 看处理状态。"
