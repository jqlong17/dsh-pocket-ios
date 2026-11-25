/**
 * 「二维码该用哪个地址」的决策。
 *
 * 抽成纯函数的原因：这段逻辑曾经出过三次事（都是用户报的）：
 *   1. Cloudflare 隧道没就绪时静默回退局域网 → 选了 CF 却扫到局域网地址
 *   2. 端口回落后 serve 指向旧端口 → 二维码里的地址连不上
 *   3. 切模式后二维码没变（其实是又生成了一张同地址的码）
 * 放在 index.js 里只能靠手测；提出来就能用测试钉住。
 */

/**
 * @typedef {Object} PairBaseInput
 * @property {string} mode            当前连接方式
 * @property {string|null} address    该方式就绪后的地址（没就绪为 null）
 * @property {string|null} lanIp      局域网 IPv4（可空）
 * @property {number} port            插件实际端口
 */

/**
 * 计算二维码基地址；返回 null 表示「现在还不能出码」。
 *
 * 规则：
 * - 有地址 → 直接用
 * - Cloudflare 没地址 → 返回 null（**绝不回退局域网**：那会让用户以为在测 CF）
 * - 其它方式没地址 → 回退局域网（至少手机在同一 Wi-Fi 时能用）
 *
 * @param {PairBaseInput} input
 * @returns {string|null}
 */
export function resolvePairBase(input) {
  const { mode, address, lanIp, port } = input
  if (address) return address
  if (mode === 'cloudflare') return null
  if (lanIp) return `http://${lanIp}:${port}`
  return null
}

/**
 * 出了码之后还要判断「这个地址现在能不能连」。
 *
 * Cloudflare 新建的隧道要几秒才对外生效，先给码会失败一次。
 *
 * @param {string} mode
 * @param {{ ok: boolean }} probeResult
 * @returns {'ready'|'wait'|'ok'}
 *   wait  = Cloudflare 地址还没生效，应提示稍候重试
 *   ready = 可以出码（Cloudflare 已探测通过）
 *   ok    = 非 Cloudflare，不需要探测
 */
export function decideAfterProbe(mode, probeResult) {
  if (mode !== 'cloudflare') return 'ok'
  // 探测不通**不再阻塞出码**：之前回 'wait' 让面板无限重试，而探测本身可能因
  // 网络抖动被 abort（实测 1.5s 超时被取消），用户看到「正在生成二维码…」一直转。
  // 改为照常出码，只把探测结果写进日志；真扫不通用户会重试一次。
  return probeResult.ok ? 'ready' : 'warn'
}
