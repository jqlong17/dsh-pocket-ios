// proxy-port.js

import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { dirname } from 'node:path'

/**
 * 插件代理端口的选取。
 *
 * 背景：DSH web 自己的端口每次重启都变，所以插件需要一个**稳定入口**给
 * tailscale serve / cloudflared / 局域网二维码使用。默认 3091。
 *
 * 但「默认」不等于「写死」：如果 3091 被别的程序占用，旧实现只打一条 warn，
 * 代理根本不监听 —— 面板显示「二维码不可用」，用户完全不知道为什么。
 * 这里把端口选择做成可回落 + 可持久化：
 *
 * - 首次启动用默认端口；
 * - 被占用就依次试下一个，最多 `maxTries` 个；
 * - 全被占用则交给系统分配（ephemeral）；
 * - 选中的端口写盘，下次启动优先用它，保证**跨重启稳定**
 *   （tailscale serve 的配置是持久化在 tailscaled 里的，端口一跳它就会指向空端口）。
 */

/** 依次尝试的端口候选：从 start 开始连续 maxTries 个。 */
export function portCandidates(start, maxTries = 10) {
  const base = Number.isInteger(start) && start > 0 ? start : 3091
  const tries = Math.max(1, Math.trunc(maxTries))
  return Array.from({ length: tries }, (_, index) => base + index)
}

/**
 * 选出第一个空闲端口。
 *
 * @param {object} options
 * @param {number[]} options.candidates - 候选端口（按优先级）。
 * @param {(port:number)=>Promise<boolean>} options.isFree - 探测端口是否可用。
 * @param {number} [options.ephemeral] - 全部占用时要系统分配的端口（0 = 让内核选）。
 * @returns {Promise<{ port: number|null, fallback: boolean }>}
 *   `port` 为 null 表示候选全占用且调用方没给 ephemeral 兜底。
 */
export async function selectProxyPort({ candidates, isFree, ephemeral = 0 }) {
  for (const port of candidates) {
    if (await isFree(port)) {
      return { port, fallback: port !== candidates[0] }
    }
  }
  if (ephemeral === null) return { port: null, fallback: true }
  return { port: ephemeral, fallback: true }
}

/** 读持久化的端口（不存在或内容非法都返回 null）。 */
export async function readPersistedPort(file) {
  try {
    const raw = (await readFile(file, 'utf8')).trim()
    const value = Number(raw)
    return Number.isInteger(value) && value > 0 && value < 65536 ? value : null
  } catch {
    return null
  }
}

/** 写持久化端口；失败不致命（下次启动退回默认而已）。 */
export async function writePersistedPort(file, port) {
  try {
    await mkdir(dirname(file), { recursive: true })
    await writeFile(file, String(port), 'utf8')
    return true
  } catch {
    return false
  }
}

/**
 * 决定这次启动用哪个端口。
 *
 * 规则（对应 UX 方案）：
 * 1. 用户显式设了 `DSH_POCKET_IOS_PROXY_PORT` → 以它为准，忽略持久化值；
 * 2. 否则优先用上次成功的端口（跨重启稳定）；
 * 3. 都没有则用默认端口。
 */
export function preferredPort({ envPort, persistedPort, defaultPort = 3091 }) {
  if (Number.isInteger(envPort) && envPort > 0) return envPort
  if (Number.isInteger(persistedPort) && persistedPort > 0) return persistedPort
  return defaultPort
}
