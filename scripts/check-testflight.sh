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

if want:
    # 按版本精确查：之前用「最近 10 个」再筛，会因为分页/排序拿不到目标构建，误报成 18。
    builds = api(f"/builds?filter[app]={app_id}&filter[version]={want}&limit=1").get("data", [])
else:
    builds = api(f"/builds?filter[app]={app_id}&limit=1&sort=-uploadedDate").get("data", [])
if not builds:
    print(f"  ❌ 查不到构建 {want or '(最新)'}"); sys.exit(1)
target = builds[0]
version = target["attributes"]["version"]
print(f"  构建 {version} · {target['attributes']['processingState']}")

# 状态刚变更时接口有几秒延迟（2026-11-26：刚加完查到 READY，10 秒后变 IN）。
# 所以轮询最多 90 秒，避免把「还在传播」误报成「没分发」。
import time as _time
internal = None
for _ in range(7):
    detail = api(f"/builds/{target['id']}/buildBetaDetail").get("data", {}).get("attributes", {})
    internal = detail.get("internalBuildState")
    if internal == "IN_BETA_TESTING":
        break
    _time.sleep(12)
print(f"  内部状态: {internal} · 外部状态: {detail.get('externalBuildState')}")

# 关键判据不是"组里有没有"，而是"内测状态是不是真的在分发"。
# 2026-11-26：15/16 加组返回 204，但状态停在 READY_FOR_BETA_TESTING，从未分发。
stuck = internal != "IN_BETA_TESTING"

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

if stuck:
    print(f"  ❌ 内测状态是 {internal}，不是 IN_BETA_TESTING —— 加了组但没真正分发")
    print("     → 修法：从组里移除后重加一次（compliance 必须先答）")
    sys.exit(1)

if missing:
    print(f"  ❌ 以下通道缺少 build {version}: {', '.join(missing)}")
    print("     → 内部/外部是两条独立通道；外部还需要 Beta 审核")
    sys.exit(1)
print("  ✅ 状态与通道都正确")
PY
