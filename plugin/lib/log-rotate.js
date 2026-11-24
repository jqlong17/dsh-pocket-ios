/**
 * 日志轮转的纯逻辑。
 *
 * 背景：`tailscale.log` 曾涨到 41 MB / 70 万行，其中 69 万行是同一条
 * `push registered`（2026-11-21 一次循环刷写）。没有轮转，日志会一直长。
 *
 * 这里只做判断与命名，真正的重命名/删除在 index.js 里做（便于单测）。
 */

/** 单份日志上限：超过就切。10 MB 足够覆盖一周的排查信息。 */
export const LOG_MAX_BYTES = 10 * 1024 * 1024

/** 保留几份历史（不含当前文件）。 */
export const LOG_KEEP = 3

/**
 * 是否需要轮转。
 * @param {number} size 当前文件字节数
 * @param {number} [limit] 上限
 */
export function shouldRotate(size, limit = LOG_MAX_BYTES) {
  return Number.isFinite(size) && size >= limit
}

/**
 * 轮转时依次重命名的目标文件：base.1 是最新的旧档。
 * 顺序为「从旧到新」的重命名顺序的反面——调用方应从大到小处理，
 * 避免 `base.2` 先被 `base.1` 覆盖。
 *
 * @param {string} base 当前日志路径
 * @param {number} [keep] 保留份数
 * @returns {{ from: string, to: string }[]}
 */
export function rotatePlan(base, keep = LOG_KEEP) {
  const plan = []
  // 先把最老的一份改名为 base.<keep>，再依次往后挪，最后 base → base.1
  for (let i = keep - 1; i >= 1; i -= 1) {
    plan.push({ from: `${base}.${i}`, to: `${base}.${i + 1}` })
  }
  plan.push({ from: base, to: `${base}.1` })
  return plan
}

/** 需要删除的最老一份路径（超过 keep 时）。 */
export function expiredPath(base, keep = LOG_KEEP) {
  return `${base}.${keep + 1}`
}
