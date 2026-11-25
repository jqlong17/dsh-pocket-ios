#!/usr/bin/env bash
#
# 发布到 App Store：打包 → 上传 → 打 tag。
#
# 设计目标（2026-11-15 与用户确认）：
#   **只保留 git tag 作为版本记录**，不再归档 ipa / dSYM。
#   因此必须严格保证「tag 指向的 commit」== 「上传到 App Store 的代码」。
#
# 靠三道闸门保证一致性：
#   1. 工作区必须干净 —— 有未提交改动时，tag 记的 commit 就不是上传的代码；
#   2. 该版本的 tag 不能已存在 —— 一版一 tag，防止同一版本重复发布；
#   3. build 号必须大于上一个 tag 的 build —— 防止误把 build 改回旧值。
# 并且 **tag 只在上传成功之后才打**：上传失败就没有 tag，不会留下「tag 了但没发」的状态。
#
# 用法：
#   ./scripts/release.sh              # 完整流程
#   ./scripts/release.sh --no-upload  # 只打包验证，不上传、不打 tag
#
# 前置：改好 Info.plist 的版本号/build；提交所有改动；~/.zshrc 配好 ASC_KEY_ID / ASC_ISSUER_ID。

set -euo pipefail
cd "$(dirname "$0")/.."

UPLOAD=1
[ "${1:-}" = "--no-upload" ] && UPLOAD=0

VERSION=$(plutil -extract CFBundleShortVersionString raw Info.plist)
BUILD=$(plutil -extract CFBundleVersion raw Info.plist)
TAG="v${VERSION}"

echo "==> 目标：$VERSION (build $BUILD)  →  tag $TAG"

# ── 闸门 1：工作区干净 ────────────────────────────────────────────
if [ -n "$(git status --porcelain)" ]; then
  echo ""
  echo "!! 工作区有未提交改动。"
  echo "   tag 记录的是 commit，未提交的改动不会进 tag——"
  echo "   那样 tag 指向的代码就和上传的产物不一致了。先提交再发布。"
  echo ""
  git status --short | head -10
  exit 1
fi

# ── 闸门 2：该版本没有 tag ────────────────────────────────────────
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
  EXISTING=$(git rev-list -n1 "$TAG" | cut -c1-7)
  echo ""
  echo "!! tag $TAG 已存在（指向 ${EXISTING}）。"
  echo "   同一版本号不能重复发布——App Store 也不接受重复 build。"
  echo "   要发新版请改 Info.plist 的版本号（并递增 build）。"
  exit 1
fi

# ── 闸门 3：build 号必须更大 ──────────────────────────────────────
PREV_TAG=$(git tag -l 'v[0-9]*' --sort=-v:refname | head -1)
if [ -n "$PREV_TAG" ]; then
  PREV_BUILD=$(git show "$PREV_TAG:Info.plist" 2>/dev/null | plutil -extract CFBundleVersion raw - 2>/dev/null || echo 0)
  if [ "${BUILD:-0}" -le "${PREV_BUILD:-0}" ] 2>/dev/null; then
    echo ""
    echo "!! build 号 $BUILD 不大于上一个版本 $PREV_TAG 的 build ${PREV_BUILD}。"
    echo "   App Store Connect 会拒绝重复的 build 号。"
    exit 1
  fi
  echo "   上一个版本 $PREV_TAG 的 build 是 ${PREV_BUILD}，本次 $BUILD ✓"
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "==> archive"
xcodebuild archive \
  -project DSHPocket.xcodeproj -scheme DSHPocket -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$WORK/DSHPocket.xcarchive" \
  -allowProvisioningUpdates >/dev/null

echo "==> export ipa"
xcodebuild -exportArchive \
  -archivePath "$WORK/DSHPocket.xcarchive" \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath "$WORK/export" \
  -allowProvisioningUpdates >/dev/null

# 校验导出的 ipa 确实是目标版本，防止 Info.plist 没生效
IPA_VERSION=$(unzip -p "$WORK/export/DSHPocket.ipa" 'Payload/DSHPocket.app/Info.plist' 2>/dev/null \
  | plutil -extract CFBundleShortVersionString raw - 2>/dev/null || echo "")
IPA_BUILD=$(unzip -p "$WORK/export/DSHPocket.ipa" 'Payload/DSHPocket.app/Info.plist' 2>/dev/null \
  | plutil -extract CFBundleVersion raw - 2>/dev/null || echo "")
if [ "$IPA_VERSION" != "$VERSION" ] || [ "$IPA_BUILD" != "$BUILD" ]; then
  echo "!! 导出的 ipa 版本是 $IPA_VERSION ($IPA_BUILD)，与 Info.plist 的 $VERSION ($BUILD) 不符"
  exit 1
fi
echo "   产物版本校验通过：$IPA_VERSION ($IPA_BUILD)"

if [ "$UPLOAD" = "0" ]; then
  echo "==> 跳过上传与打 tag（--no-upload）"
  exit 0
fi

echo "==> 上传到 App Store Connect"
OUT=$(zsh -c 'source ~/.zshrc 2>/dev/null; env -u all_proxy -u ALL_PROXY -u http_proxy -u HTTP_PROXY \
      xcrun altool --upload-app -f '"$WORK"'/export/DSHPocket.ipa -t ios \
      --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" --output-format json' 2>&1) || {
  echo "$OUT" | tail -15
  echo "!! 上传失败，未打 tag。修好后重跑本脚本。"
  exit 1
}
echo "$OUT" | grep -E "UPLOAD SUCCEEDED|Delivery UUID|ERROR" | head -4 || echo "$OUT" | tail -5

# ── 上传成功后才打 tag（顺序不能反）────────────────────────────────
echo "==> 打 tag $TAG"
git tag -a "$TAG" -m "$VERSION ($BUILD)"
git push origin "$TAG" 2>&1 | tail -2

echo ""
echo "==> 完成"
echo "    tag      $TAG → $(git rev-list -n1 "$TAG" | cut -c1-7)"
echo "    版本     $VERSION (build $BUILD)"
echo "    下一步   去 App Store Connect 创建版本、关联 build、提交审核"
