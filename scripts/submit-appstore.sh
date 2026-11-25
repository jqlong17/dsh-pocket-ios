#!/usr/bin/env bash
#
# 提交一个新版本到 App Store 审核，并设置「审核通过后自动上架」。
#
# 用法：
#   ./scripts/submit-appstore.sh <版本号> <build号> [更新说明文件]
#
# 例：
#   ./scripts/submit-appstore.sh 1.1.2 12 docs/whatsnew-1.1.2.md
#
# 前提：
#   · 构建已经上传并被 Apple 处理完（processingState = VALID）
#   · ~/.zshrc 里有 ASC_KEY_ID / ASC_ISSUER_ID（altool 生成 JWT 用）
#   · 证书私钥在 ~/.appstoreconnect/private_keys/AuthKey_<ID>.p8
#
# 它做的事情（就是 2026-11-24 手动走通的那 8 步）：
#   1. 生成 JWT
#   2. 新建版本草稿，releaseType 直接设 AFTER_APPROVAL（审核通过自动上架）
#   3. 取上一版的本地化作为模板（Apple 会自动克隆，这里兜底）
#   4. 写入 whatsNew（若给了说明文件）
#   5. 关联 build
#   6. 建 reviewSubmissions → 加条目 → 提交
#   7. 打印最终状态
#
# 为什么 releaseType 要在这里设：
#   版本一旦进入 PENDING_DEVELOPER_RELEASE，releaseType 就改不动了
#   （API 直接报 "cannot be 'AFTER_APPROVAL' if version state is ..."）。
#   所以必须在创建/提交阶段就定好，否则每次都得人工点发布。
set -euo pipefail

APP_ID="${APP_ID:-6832288744}"
API_BASE="https://api.appstoreconnect.apple.com/v1"

VERSION="${1:-}"
BUILD="${2:-}"
NOTES_FILE="${3:-}"

if [[ -z "$VERSION" || -z "$BUILD" ]]; then
  echo "用法: $0 <版本号> <build号> [更新说明文件]" >&2
  exit 2
fi

# shellcheck disable=SC1090
set -a; source ~/.zshrc >/dev/null 2>&1; set +a
: "${ASC_KEY_ID:?缺少 ASC_KEY_ID（应在 ~/.zshrc）}"
: "${ASC_ISSUER_ID:?缺少 ASC_ISSUER_ID（应在 ~/.zshrc）}"

say() { printf '  %s\n' "$*"; }
die() { printf '  ❌ %s\n' "$*" >&2; exit 1; }

# ── JWT（altool 输出里有噪音，只取像 JWT 的那一行）─────────────
JWT=$(xcrun altool --generate-jwt --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1 \
      | awk 'length($0) > 200 && index($0, ".") > 0 { print; exit }')
[[ -n "$JWT" ]] || die "生成 JWT 失败"

api() { # api <METHOD> <PATH> [BODY]
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -sS --max-time 40 -X "$method" \
      -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
      -d "$body" "$API_BASE$path"
  else
    curl -sS --max-time 40 -X "$method" -H "Authorization: Bearer $JWT" "$API_BASE$path"
  fi
}

# ── 0. 校验 build ────────────────────────────────────────────────
say "查找 build $BUILD ..."
BUILDS=$(api GET "/builds?filter%5Bapp%5D=$APP_ID&filter%5Bversion%5D=$BUILD&limit=1")
BUILD_ID=$(printf '%s' "$BUILDS" | python3 -c 'import sys,json;d=json.load(sys.stdin);print((d.get("data") or [{}])[0].get("id",""))')
[[ -n "$BUILD_ID" ]] || die "找不到 build ${BUILD}（先上传并等处理完）"
STATE=$(printf '%s' "$BUILDS" | python3 -c 'import sys,json;d=json.load(sys.stdin);print((d.get("data") or [{}])[0]["attributes"]["processingState"])')
say "build id=$BUILD_ID state=$STATE"
[[ "$STATE" == "VALID" ]] || die "build 状态是 ${STATE}，不是 VALID"

# ── 1. 已有同版本草稿则复用，否则新建 ───────────────────────────
EXIST=$(api GET "/apps/$APP_ID/appStoreVersions?filter%5BversionString%5D=$VERSION&limit=1")
VER_ID=$(printf '%s' "$EXIST" | python3 -c 'import sys,json;d=json.load(sys.stdin);print((d.get("data") or [{}])[0].get("id",""))')

if [[ -n "$VER_ID" ]]; then
  say "复用已存在的版本草稿 $VER_ID"
  api PATCH "/appStoreVersions/$VER_ID" \
    "{\"data\":{\"type\":\"appStoreVersions\",\"id\":\"$VER_ID\",\"attributes\":{\"releaseType\":\"AFTER_APPROVAL\"}}}" >/dev/null || true
else
  say "新建版本 ${VERSION}（AFTER_APPROVAL：审核通过自动上架）"
  CREATED=$(api POST "/appStoreVersions" \
    "{\"data\":{\"type\":\"appStoreVersions\",\"attributes\":{\"platform\":\"IOS\",\"versionString\":\"$VERSION\",\"releaseType\":\"AFTER_APPROVAL\"},\"relationships\":{\"app\":{\"data\":{\"type\":\"apps\",\"id\":\"$APP_ID\"}}}}}")
  VER_ID=$(printf '%s' "$CREATED" | python3 -c 'import sys,json;d=json.load(sys.stdin);print((d.get("data") or {}).get("id",""))')
  [[ -n "$VER_ID" ]] || die "创建版本失败: $CREATED"
fi

# ── 2. 关联 build ───────────────────────────────────────────────
say "关联 build ..."
api PATCH "/appStoreVersions/$VER_ID/relationships/build" \
  "{\"data\":{\"type\":\"builds\",\"id\":\"$BUILD_ID\"}}" >/dev/null

# ── 3. whatsNew（可选）──────────────────────────────────────────
if [[ -n "$NOTES_FILE" ]]; then
  [[ -f "$NOTES_FILE" ]] || die "找不到说明文件 $NOTES_FILE"
  say "写入 whatsNew（来源 ${NOTES_FILE}）"
  LOCS=$(api GET "/appStoreVersions/$VER_ID/appStoreVersionLocalizations")
  printf '%s' "$LOCS" | python3 -c '
import sys, json, pathlib
d = json.load(sys.stdin)
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
for l in d.get("data", []):
    vid = l["id"]; loc = l["attributes"].get("locale", "")
    body = {"data": {"type": "appStoreVersionLocalizations", "id": vid, "attributes": {"whatsNew": text}}}
    pathlib.Path(f"/tmp/whatsnew_{vid}.json").write_text(json.dumps(body, ensure_ascii=False), encoding="utf-8")
    print(vid)
' "$NOTES_FILE" | while read -r vid; do
    [[ -z "$vid" ]] && continue
    curl -sS --max-time 40 -X PATCH -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
      -d @"/tmp/whatsnew_$vid.json" "$API_BASE/appStoreVersionLocalizations/$vid" >/dev/null || true
  done
fi

# ── 4. 提交审核 ─────────────────────────────────────────────────
say "创建审核提交单 ..."
RS=$(api POST "/reviewSubmissions" \
  "{\"data\":{\"type\":\"reviewSubmissions\",\"attributes\":{\"platform\":\"IOS\"},\"relationships\":{\"app\":{\"data\":{\"type\":\"apps\",\"id\":\"$APP_ID\"}}}}}")
RS_ID=$(printf '%s' "$RS" | python3 -c 'import sys,json;d=json.load(sys.stdin);print((d.get("data") or {}).get("id",""))')
[[ -n "$RS_ID" ]] || die "创建提交单失败: $RS"

say "加入版本条目 ..."
api POST "/reviewSubmissionItems" \
  "{\"data\":{\"type\":\"reviewSubmissionItems\",\"relationships\":{\"reviewSubmission\":{\"data\":{\"type\":\"reviewSubmissions\",\"id\":\"$RS_ID\"}},\"appStoreVersion\":{\"data\":{\"type\":\"appStoreVersions\",\"id\":\"$VER_ID\"}}}}}" >/dev/null

say "提交 ..."
api PATCH "/reviewSubmissions/$RS_ID" \
  "{\"data\":{\"type\":\"reviewSubmissions\",\"id\":\"$RS_ID\",\"attributes\":{\"submitted\":true}}}" >/dev/null

# ── 5. 结果 ─────────────────────────────────────────────────────
FINAL=$(api GET "/appStoreVersions/$VER_ID?fields%5BappStoreVersions%5D=versionString,appStoreState,releaseType")
printf '%s' "$FINAL" | python3 -c "
import sys, json
a = json.load(sys.stdin)['data']['attributes']
print('  ✅', a.get('versionString'), '·', a.get('appStoreState'), '· 发布方式', a.get('releaseType'))
"
say "审核通过后会自动上架，无需再手动点「发布」。"
