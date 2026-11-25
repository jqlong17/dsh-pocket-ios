#!/usr/bin/env bash
# 检查「插件实际监听端口」与「tailscale serve 指向端口」是否一致。
#
# 背景：端口从 3091 回落到 3092 后，serve 仍指向 3091，于是二维码里的地址
# 连不到插件，App 报「二维码已过期」。这个脚本一眼看出是否对得上。
#
# 用法：./scripts/check-serve-port.sh
set -uo pipefail

TS="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
say() { printf '  %s\n' "$*"; }

PLUGIN_PORT=$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null \
  | awk '/:309[0-9]/ {n=split($9,a,":"); print a[n]}' | sort -u | head -1)

SERVE_OUT=$("$TS" serve status 2>/dev/null)
SERVE_PORT=$(printf '%s' "$SERVE_OUT" | grep -oE 'proxy +[^ ]+:[0-9]+' | grep -oE '[0-9]+$' | head -1)
SERVE_URL=$(printf '%s' "$SERVE_OUT" | grep -oE 'https://[^ ]+' | head -1)

say "插件监听端口: ${PLUGIN_PORT:-none}"
say "serve 指向端口: ${SERVE_PORT:-none}"
say "tailnet 地址:   ${SERVE_URL:-none}"

if [ -z "$PLUGIN_PORT" ] || [ -z "$SERVE_PORT" ]; then
  say "FAIL 信息不全，先确认 DSH 在跑、且连接方式是 Tailscale"
  exit 1
fi

if [ "$PLUGIN_PORT" = "$SERVE_PORT" ]; then
  say "OK 端口一致"
else
  say "FAIL 端口不一致 —— 扫码会失败（提示「二维码已过期」）"
  say "     修：$TS serve --bg $PLUGIN_PORT"
fi

if [ -n "$SERVE_URL" ]; then
  CODE=$(curl -sS --max-time 8 --noproxy '*' -o /dev/null -w '%{http_code}' "$SERVE_URL/" 2>/dev/null)
  case "$CODE" in
    200|401|403) say "OK 地址可达（HTTP ${CODE}；401/403 是插件鉴权，正常）" ;;
    *)           say "FAIL 地址不可达（HTTP ${CODE:-000}）" ;;
  esac
fi
