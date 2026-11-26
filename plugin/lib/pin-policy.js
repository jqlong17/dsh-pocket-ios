import { randomInt } from 'node:crypto'

/**
 * 访问密码与登录限流的纯逻辑。
 *
 * 单独成文件的原因：这两条都是「能被自动检查」的部分——密码格式、锁定行为，
 * 都可以用单测锁住；放进 index.js 就只能靠人工回归。
 */

const ALNUM = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789'
const LETTERS = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz'
const DIGITS = '23456789'

/**
 * 生成访问密码：12 位，必须同时含字母和数字。
 *
 * 旧的 8 位纯数字只有约 26 bit 熵，配合公网隧道不够；12 位混合字符约 70 bit，
 * 再叠加限流，暴力枚举不再现实。去掉了 0/O/1/l/I 这类抄写易错的字符。
 * readPin 允许 8–64 位，所以老用户的旧密码继续有效，不会被强制更换。
 *
 * @param {(min: number, max: number) => number} [rand] 便于测试注入
 */
export function randomPin(rand = randomInt) {
  const chars = [LETTERS[rand(0, LETTERS.length)], DIGITS[rand(0, DIGITS.length)]]
  while (chars.length < 12) chars.push(ALNUM[rand(0, ALNUM.length)])
  for (let i = chars.length - 1; i > 0; i--) {
    const j = rand(0, i + 1)
    const t = chars[i]
    chars[i] = chars[j]
    chars[j] = t
  }
  return chars.join('')
}

/**
 * 登录失败限流。
 *
 * 为什么必须有：login 端点对公网隧道可达，而密码曾经只有 26 bit。
 * 失败达到 maxFails 后锁定，之后每次再触发锁定都逐级加长（默认 5/15/60 分钟）。
 * 只按来源 IP 记账；成功登录立刻清零，正常用户不受影响。
 */
export function createLoginLimiter({
  maxFails = 5,
  windowMs = 10 * 60 * 1000,
  lockStepsMs = [5 * 60 * 1000, 15 * 60 * 1000, 60 * 60 * 1000],
} = {}) {
  const records = new Map()

  return {
    /** @returns {{retryAfter: number}|null} */
    check(ip, now = Date.now()) {
      const rec = records.get(ip)
      if (rec && rec.lockedUntil && now < rec.lockedUntil) {
        return { retryAfter: Math.max(1, Math.ceil((rec.lockedUntil - now) / 1000)) }
      }
      return null
    },

    /** @returns {number} 本次触发的锁定时长（毫秒），没触发返回 0 */
    recordFailure(ip, now = Date.now()) {
      const rec = records.get(ip) ?? { fails: 0, firstAt: now, locks: 0, lockedUntil: 0 }
      if (now - rec.firstAt > windowMs) {
        rec.fails = 0
        rec.firstAt = now
      }
      rec.fails += 1
      if (rec.fails >= maxFails) {
        const step = lockStepsMs[Math.min(rec.locks, lockStepsMs.length - 1)]
        rec.lockedUntil = now + step
        rec.locks += 1
        rec.fails = 0
        records.set(ip, rec)
        return step
      }
      records.set(ip, rec)
      return 0
    },

    clear(ip) {
      records.delete(ip)
    },

    get size() {
      return records.size
    },
  }
}

/**
 * 取「真正的客户端标识」用于限流。
 *
 * 为什么不能直接用 socket.remoteAddress：经 tailscale serve / cloudflared 转发时，
 * remoteAddress 恒为 127.0.0.1，所有用户会共用一个计数桶——一个人的失败会锁住所有人，
 * 攻击者也能借此做拒绝服务。优先用转发头，最后才退回 socket 地址。
 */
export function clientKey(headers = {}, remoteAddress = '') {
  const xff = String(headers['x-forwarded-for'] ?? '').split(',')[0].trim()
  if (xff) return xff
  const cf = String(headers['cf-connecting-ip'] ?? '').trim()
  if (cf) return cf
  const login = String(headers['tailscale-user-login'] ?? '').trim()
  if (login) return `user:${login}`
  return String(remoteAddress || 'unknown')
}
