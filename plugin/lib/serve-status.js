/**
 * 解析 `tailscale serve status` 的输出。
 *
 * 为什么需要：`ensureTailscaleServe` 以前只判断「有没有 serve 地址」，
 * 不判断它指向哪个端口。端口回落后（3091 被占 → 3092），serve 仍指向 3091，
 * 于是二维码里的地址连不到插件，App 表现为「二维码已过期」（2026-11-25 实锤）。
 *
 * 输出样例：
 *   https://host.tailnet.ts.net (tailnet only)
 *   |-- / proxy http://127.0.0.1:3092
 *
 * @param {string} text
 * @returns {{ url: string|null, port: number|null }}
 */
export function parseServeStatus(text) {
  const raw = String(text ?? '')
  const urlMatch = raw.match(/https:\/\/[^\s)]+/)
  const portMatch = raw.match(/proxy\s+(?:https?:\/\/)?[^\s:]+:(\d+)/)
  return {
    url: urlMatch ? urlMatch[0].replace(/\/$/, '') : null,
    port: portMatch ? Number(portMatch[1]) : null,
  }
}

/**
 * serve 是否需要重新指向。
 *
 * - 没有地址 → 需要（去做 --bg）
 * - 有地址但端口不同 → 需要（端口回落过）
 * - 有地址、端口一致 → 不需要（避免每次切模式都重写）
 * - 有地址但解析不出端口 → 不动（保守，别把能用的配置改坏）
 *
 * @param {{ url: string|null, port: number|null }} parsed
 * @param {number} port 当前实际监听端口
 */
export function needsRepoint(parsed, port) {
  if (!parsed?.url) return true
  if (parsed.port === null || parsed.port === undefined) return false
  return Number(parsed.port) !== Number(port)
}
