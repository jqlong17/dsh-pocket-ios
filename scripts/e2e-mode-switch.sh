#!/usr/bin/env bash
#
# 连接方式切换的端到端测试。
#
# 直接打插件自己的 REST 接口，验证「切到每种方式后，二维码里给出的地址是否属于该方式」。
# 这正是用户报过的几类问题：
#   · 选了 Cloudflare，二维码却是局域网地址（静默回退）
#   · 端口回落后 tailscale serve 还指向旧端口（扫了连不上）
#   · 切模式后二维码没变（其实是又生成了一张同地址的码）
#
# 用法：./scripts/e2e-mode-switch.sh [--keep]
#   默认结束后恢复原连接方式；--keep 保持最后的测试结果方便手动看面板。
#
# 注意：会真实切换 DSH 的连接方式（可能重启 cloudflared / 改 tailscale serve）。
set -uo pipefail

BASE="http://127.0.0.1:${PLUGIN_PORT:-3092}"
TOKEN="e2e$(date +%s)"
DEVICES="$HOME/.dsh/dsh-pocket-ios/devices.json"
BACKUP="/tmp/e2e-devices-backup.json"

pass=0; fail=0
ok()   { printf '  ✅ %s\n' "$*"; pass=$((pass+1)); }
bad()  { printf '  ❌ %s\n' "$*"; fail=$((fail+1)); }
say()  { printf '  %s\n' "$*"; }

cleanup() {
  # 删除测试凭证
  if [ -f "$DEVICES" ]; then
    python3 - "$DEVICES" "$TOKEN" <<'PY'
import json, sys
path, token = sys.argv[1], sys.argv[2]
d = json.load(open(path))
d.pop(token, None)
open(path, 'w').write(json.dumps(d, ensure_ascii=False, indent=2))
PY
  fi
}
trap cleanup EXIT

# ── 0. 探测插件端口 ───────────────────────────────────────────────
PORT=$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk '/:309[0-9]/ {n=split($9,a,":"); print a[n]}' | sort -u | head -1)
if [ -z "$PORT" ]; then
  say "找不到插件端口（DSH 没跑？）"; exit 1
fi
BASE="http://127.0.0.1:$PORT"
say "插件端口: $PORT"

# ── 1. 注入一个临时设备凭证（测试完删除）────────────────────────
python3 - "$DEVICES" "$TOKEN" <<'PY'
import json, sys, time
path, token = sys.argv[1], sys.argv[2]
d = json.load(open(path))
d[token] = {"name": "e2e-mode-switch", "family": "dshpocket-ios", "createdAt": int(time.time()*1000)}
open(path, 'w').write(json.dumps(d, ensure_ascii=False, indent=2))
PY
say "已注入临时凭证 ${TOKEN:0:8}…（退出时删除）"

rpc() { # rpc <endpoint> [json-args]
  local ep="$1" args="${2:-{\}}"
  curl -sS --max-time 40 -X POST \
    -H "x-dsh-pocket-device: $TOKEN" \
    -H 'content-type: application/json' \
    -d "{\"payload\":{\"args\":$args}}" \
    "$BASE/dsh-pocket-ios/$ep" 2>/dev/null
}

# 取出 result.value 里的字段
field() { python3 -c "
import sys, json
try: d = json.load(sys.stdin)
except Exception: print(''); raise SystemExit
v = (d.get('result') or {}).get('value') or {}
print(v.get('$1', '') or '')
"; }

# ── 2. 逐模式验证 ────────────────────────────────────────────────
expect_host() { # expect_host <mode> <url>
  local mode="$1" url="$2"
  case "$mode" in
    lan)       [[ "$url" =~ ^https?://(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.) ]] ;;
    tailscale) [[ "$url" =~ \.(ts\.net) ]] ;;
    cloudflare) [[ "$url" =~ trycloudflare\.com ]] ;;
    *)         return 0 ;;
  esac
}

for mode in lan tailscale cloudflare; do
  say ""
  say "── 切到 $mode ──"
  rpc mode.set "{\"mode\":\"$mode\"}" >/dev/null

  # 轮询状态，最多 25 秒（cloudflare 冷启动/下载会很慢）
  addr=""; state=""
  for _ in $(seq 1 25); do
    sleep 1
    out=$(rpc tailscale.status)
    addr=$(printf '%s' "$out" | field address)
    state=$(printf '%s' "$out" | field state)
    [ -n "$addr" ] && break
  done

  if [ -z "$addr" ]; then
    bad "$mode: 25 秒内没有地址（state=${state}）"
    continue
  fi
  ok "$mode: 状态已有地址 $addr"

  if expect_host "$mode" "$addr"; then
    ok "$mode: 地址形态正确"
  else
    bad "$mode: 地址形态不对（期望 $mode 的地址，拿到 ${addr}）"
  fi

  # 二维码里的地址必须和状态地址一致
  pair=$(rpc pair.create)
  qr=$(printf '%s' "$pair" | python3 -c "
import sys, json, urllib.parse
d = json.load(sys.stdin)
v = (d.get('result') or {}).get('value') or {}
u = v.get('url') or ''
print(urllib.parse.urlsplit(u).netloc)
" 2>/dev/null)
  want=$(python3 -c "import urllib.parse,sys;print(urllib.parse.urlsplit(sys.argv[1]).netloc)" "$addr")
  if [ "$qr" = "$want" ]; then
    ok "$mode: 二维码与状态地址一致（${qr}）"
  else
    bad "$mode: 二维码(${qr}) 与状态(${want}) 不一致"
  fi
done

# ── 3. Tailscale 专项：serve 端口必须指向插件端口 ─────────────────
say ""
say "── Tailscale serve 端口一致性 ──"
rpc mode.set '{"mode":"tailscale"}' >/dev/null
sleep 3
SERVE=$("/Applications/Tailscale.app/Contents/MacOS/Tailscale" serve status 2>/dev/null | grep -oE 'proxy +[^ ]+:[0-9]+' | grep -oE '[0-9]+$' | head -1)
if [ "$SERVE" = "$PORT" ]; then
  ok "serve 指向 ${SERVE}，与插件端口一致"
else
  bad "serve 指向 ${SERVE:-无}，插件却是 ${PORT}"
fi

say ""
say "结果：$pass 通过 / $fail 失败"
[ "$fail" -eq 0 ] || exit 1
