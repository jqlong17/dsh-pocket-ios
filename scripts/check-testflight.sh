#!/usr/bin/env bash
#
# TestFlight 可见性检查：某个构建到底进没进「分发通道」。
#
# 为什么需要（2026-11-26 踩过的坑）：
#   构建 15/16/17 只加进了「内部测试」组，而用户的 TestFlight 登录的是
#   「Public Beta（外部）」组的外部测试者账号 —— 于是他只能看到外部组里的 build 14，
#   连查三次内部组都"在"，就误以为已经推过去了。
#   **"加进了某个组" ≠ "目标用户看得到"**：内部/外部是两条独立通道。
#
# 用法：
#   ./scripts/check-testflight.sh            # 检查最新构建
#   ./scripts/check-testflight.sh 17         # 检查指定 build 号
#
# 退出码：0 = 两个组都可见；1 = 有组缺失（会打印缺哪个）。
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

APP_ID=6832288744
BUILD="${1:-}"

set -a; . "$HOME/.zshrc" >/dev/null 2>&1; set +a
if [ -z "${ASC_KEY_ID:-}" ] || [ -z "${ASC_ISSUER_ID:-}" ]; then
  echo "  ❌ 缺少 ASC_KEY_ID / ASC_ISSUER_ID（应在 ~/.zshrc）"
  exit 1
fi

TOKEN_FILE=$(mktemp)
xcrun altool --generate-jwt --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" > "$TOKEN_FILE" 2>&1
TOKEN=$(grep -oE "eyJ[A-Za-z0-9_.-]{100,}" "$TOKEN_FILE" | head -1)
rm -f "$TOKEN_FILE"
[ -n "$TOKEN" ] || { echo "  ❌ 生成 API token 失败"; exit 1; }

python3 - "$TOKEN" "$APP_ID" "$BUILD" << 'PY'
import json, sys, urllib.request

token, app_id, want = sys.argv[1], sys.argv[2], sys.argv[3]
BASE = "https://api.appstoreconnect.apple.com/v1"

def api(path):
    req = urllib.request.Request(BASE + path, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read() or b"{}")

builds = api(f"/builds?filter[app]={app_id}&limit=10&sort=-uploadedDate").get("data", [])
if not builds:
    print("  ❌ 查不到任何构建"); sys.exit(1)
target = next((b for b in builds if b["attributes"]["version"] == want), builds[0]) if want else builds[0]
version = target["attributes"]["version"]
print(f"  构建 {version} · {target['attributes']['processingState']}")

detail = api(f"/builds/{target['id']}/buildBetaDetail").get("data", {}).get("attributes", {})
print(f"  内部状态: {detail.get('internalBuildState')} · 外部状态: {detail.get('externalBuildState')}")

groups = api(f"/betaGroups?filter[app]={app_id}&limit=20").get("data", [])
missing = []
for g in groups:
    name = g["attributes"].get("name")
    members = api(f"/betaGroups/{g['id']}/builds?limit=50").get("data", [])
    versions = {b["attributes"]["version"] for b in members}
    ok = version in versions
    print(f"  组「{name}」: {'✅ 有' if ok else '❌ 缺'}（现有: {', '.join(sorted(versions, key=lambda x: int(x))[-6:])}）")
    if not ok:
        missing.append(name)

if missing:
    print(f"  ❌ 以下通道缺少 build {version}: {', '.join(missing)}")
    print("     → 内部/外部是两条独立通道；外部还需要 Beta 审核")
    sys.exit(1)
print("  ✅ 所有测试通道都包含该构建")
PY
