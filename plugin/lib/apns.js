/**
 * APNs 发送：ES256 JWT + HTTP/2。
 *
 * 两个容易踩的点（本仓库都踩过）：
 * 1. **ES256 的签名必须是 raw r||s（64 字节）**，Node 的 `crypto.sign` 给的是 DER，
 *    直接塞进 JWT 会被 APNs 拒绝（403 InvalidProviderToken）。
 * 2. **Sandbox 与 Production 是两个域名**，TestFlight/调试走 sandbox，App Store 走生产。
 */
import { createPrivateKey, sign } from 'node:crypto'
import { connect } from 'node:http2'

export const SANDBOX_HOST = 'https://api.sandbox.push.apple.com'
export const PRODUCTION_HOST = 'https://api.push.apple.com'

/** JWT 里 iat 的有效期是 1 小时，APNs 要求 20 分钟以上刷新一次。 */
export const JWT_REFRESH_MS = 20 * 60 * 1000

/** DER(SEQUENCE{INTEGER r, INTEGER s}) → 64 字节 raw r||s。 */
export function derToRawSignature(der) {
  if (!Buffer.isBuffer(der) || der.length < 8 || der[0] !== 0x30) {
    throw new Error('不是合法的 DER 签名')
  }
  let offset = 1
  let length = der[offset]
  offset += 1
  if (length & 0x80) {
    // 长格式长度，跳过长度字节
    offset += length & 0x7f
  }
  if (der[offset] !== 0x02) throw new Error('DER r 段缺失')
  offset += 1
  const rLength = der[offset]
  offset += 1
  let r = der.subarray(offset, offset + rLength)
  offset += rLength
  if (der[offset] !== 0x02) throw new Error('DER s 段缺失')
  offset += 1
  const sLength = der[offset]
  offset += 1
  let s = der.subarray(offset, offset + sLength)

  // DER 的整数是补码，最高位为 1 时会多一个 0x00 前导字节
  if (r.length > 32 && r[0] === 0x00) r = r.subarray(1)
  if (s.length > 32 && s[0] === 0x00) s = s.subarray(1)
  if (r.length > 32 || s.length > 32) throw new Error('DER 分量超长')

  const out = Buffer.alloc(64)
  r.copy(out, 32 - r.length)
  s.copy(out, 64 - s.length)
  return out
}

function base64url(input) {
  return Buffer.from(input).toString('base64url')
}

/** 生成 APNs 用的 ES256 JWT。 */
export function makeProviderToken({ keyId, teamId, privateKeyPem, issuedAt = Math.floor(Date.now() / 1000) }) {
  if (!keyId || !teamId || !privateKeyPem) throw new Error('APNs 凭证不完整')
  const header = base64url(JSON.stringify({ alg: 'ES256', kid: keyId }))
  const payload = base64url(JSON.stringify({ iss: teamId, iat: issuedAt }))
  const signingInput = `${header}.${payload}`
  const key = createPrivateKey(privateKeyPem)
  const der = sign('sha256', Buffer.from(signingInput), key)
  const raw = derToRawSignature(der)
  return `${signingInput}.${raw.toString('base64url')}`
}

/** 缓存 token，避免每推一条都签一次。 */
export class ProviderTokenCache {
  constructor({ keyId, teamId, privateKeyPem, now = () => Date.now() }) {
    this.keyId = keyId
    this.teamId = teamId
    this.privateKeyPem = privateKeyPem
    this.now = now
    this.token = null
    this.issuedAt = 0
  }

  get() {
    const age = this.now() - this.issuedAt
    if (this.token && age < JWT_REFRESH_MS) return this.token
    this.token = makeProviderToken({
      keyId: this.keyId,
      teamId: this.teamId,
      privateKeyPem: this.privateKeyPem,
      issuedAt: Math.floor(this.now() / 1000),
    })
    this.issuedAt = this.now()
    return this.token
  }
}

/**
 * 发一条推送。
 * @returns {Promise<{ok: boolean, status?: number, reason?: string}>}
 *   reason 为 'Unregistered'/'BadDeviceToken' 时调用方应删除该 token。
 */
export async function sendPush({
  token,
  payload,
  jwt,
  environment = 'production',
  topic,
  timeoutMs = 10_000,
}) {
  const host = environment === 'sandbox' ? SANDBOX_HOST : PRODUCTION_HOST
  return new Promise((resolve) => {
    let settled = false
    const finish = (value) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      try { client.close() } catch { /* 已关闭 */ }
      resolve(value)
    }

    const timer = setTimeout(() => finish({ ok: false, reason: 'timeout' }), timeoutMs)
    let client
    try {
      client = connect(host)
    } catch (error) {
      finish({ ok: false, reason: `connect: ${error?.message ?? error}` })
      return
    }

    client.on('error', (error) => finish({ ok: false, reason: `stream: ${error?.message ?? error}` }))

    const headers = {
      'authorization': `bearer ${jwt}`,
      'apns-topic': topic,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'content-type': 'application/json',
    }
    const stream = client.request({ ':method': 'POST', ':path': `/3/device/${token}`, ...headers })
    let body = ''
    stream.setEncoding('utf8')
    stream.on('response', (responseHeaders) => {
      const status = Number(responseHeaders[':status'] ?? 0)
      stream.on('data', (chunk) => { body += chunk })
      stream.on('end', () => {
        if (status === 200) {
          finish({ ok: true, status })
        } else {
          let reason = ''
          try { reason = JSON.parse(body)?.reason ?? '' } catch { /* 非 JSON */ }
          finish({ ok: false, status, reason: reason || body.slice(0, 120) })
        }
      })
    })
    stream.on('error', (error) => finish({ ok: false, reason: `stream: ${error?.message ?? error}` }))
    stream.end(JSON.stringify(payload))
  })
}
