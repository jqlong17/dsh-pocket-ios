// 跨机器 DSH 调用：向另一个 DSH 上的会话发消息并读回复。
//
// 协议是实测出来的，四条都不能改：
//   ① 首站 `/dsh-pocket-ios/peer/pair`，对方靠 tailnet 身份签发 dsh-pocket-device。
//      必须跟随它的重定向与 set-cookie，否则拿到的凭据不完整。
//   ② 用 device cookie `POST /dsh-pocket-ios/refresh` 拿 302，**再跟一次 GET** 才会
//      下发 dsh-auth-*。少了这步，后续 /api/* 全是 401。
//   ③ 必须 HTTP/2。tailscale serve → tailscaled → 127.0.0.1 这条链上 http/1.1 会被 RST。
//   ④ `session/page` 的参数是 `address{kind,sessionId} + maxMessages`，
//      `session/prompt` 是 `request{...}`；形状不同，混用会被 gateway 判 input-invalid。
import http2 from 'node:http2'

const CHANNEL = '/dsh-pocket-ios'

/** 一次连接内复用同一个 h2 session，避免每个请求都重新握手。 */
function openClient(address) {
  const base = String(address ?? '').replace(/\/$/, '')
  if (!base) throw new Error('节点地址为空')
  const client = http2.connect(base)
  return { client, base }
}

function request(client, { method = 'POST', path, body, cookie, timeout = 20000 }) {
  return new Promise((resolve, reject) => {
    const payload = body == null ? null : (typeof body === 'string' ? body : JSON.stringify(body))
    const headers = { ':method': method, ':path': path }
    if (payload != null) {
      headers['content-type'] = 'application/json'
      headers['content-length'] = Buffer.byteLength(payload)
    }
    if (cookie) headers.cookie = cookie

    const req = client.request(headers)
    const timer = setTimeout(() => req.destroy(new Error('请求超时')), timeout)
    let status = 0
    let resHeaders = {}
    let data = ''
    req.on('response', (h) => { status = h[':status']; resHeaders = h })
    req.on('data', (c) => { data += c })
    req.on('end', () => {
      clearTimeout(timer)
      resolve({ status, headers: resHeaders, body: data })
    })
    req.on('error', (e) => { clearTimeout(timer); reject(new Error(`连接失败: ${e.code ?? e.message}`)) })
    req.end(payload ?? undefined)
  })
}

function collectCookies(jar, headers) {
  const sc = headers['set-cookie']
  for (const raw of (Array.isArray(sc) ? sc : sc ? [sc] : [])) {
    const kv = raw.split(';')[0]
    const i = kv.indexOf('=')
    if (i > 0) jar[kv.slice(0, i).trim()] = kv.slice(i + 1).trim()
  }
}

const cookieHeader = (jar) => Object.entries(jar).map(([k, v]) => `${k}=${v}`).join('; ')

/**
 * 拿到对方 DSH 的登录态。
 * 顺序不能换：peer/pair 给设备凭据 → refresh 的 302 → 跟到目标页才下发 dsh-auth。
 */
async function authenticate(client, base) {
  const jar = {}

  const pair = await request(client, { method: 'GET', path: `${CHANNEL}/peer/pair` })
  if (pair.status !== 200) {
    throw new Error(`对方拒绝了 tailnet 互信（HTTP ${pair.status}）: ${pair.body.slice(0, 160)}`)
  }
  collectCookies(jar, pair.headers)

  const refresh = await request(client, {
    method: 'POST',
    path: `${CHANNEL}/refresh`,
    body: '',
    cookie: cookieHeader(jar),
  })
  collectCookies(jar, refresh.headers)

  const location = refresh.headers.location
  if (refresh.status >= 300 && refresh.status < 400 && location) {
    const target = new URL(String(location), base)
    const follow = await request(client, {
      method: 'GET',
      path: target.pathname + target.search,
      body: null,
      cookie: cookieHeader(jar),
    })
    collectCookies(jar, follow.headers)
  }

  const auth = Object.keys(jar).some((k) => k.startsWith('dsh-auth-'))
  if (!auth) throw new Error('没换到 dsh-auth，对方可能未登录')
  return cookieHeader(jar)
}

async function rpc(client, cookie, method, args) {
  const res = await request(client, {
    method: 'POST',
    path: `/api/${method}`,
    cookie,
    body: { type: 'client-request', rpcId: crypto.randomUUID(), method, payload: { args } },
  })
  if (res.status < 200 || res.status >= 300) throw new Error(`HTTP ${res.status}: ${res.body.slice(0, 160)}`)
  let parsed
  try { parsed = JSON.parse(res.body) } catch { throw new Error('对方返回的不是 JSON') }
  if (parsed.error) throw new Error(String(parsed.error.message ?? JSON.stringify(parsed.error)).slice(0, 200))
  if (parsed.result && parsed.result.ok === false) {
    const err = parsed.result.error
    throw new Error(String(err?.message ?? JSON.stringify(err ?? parsed.result)).slice(0, 200))
  }
  return parsed.result?.value ?? parsed.result
}

/** 列出对方会话。参数形状是 `_request`，和 prompt 的 `request` 不同。 */
export async function listPeerSessions(address, { limit = 20 } = {}) {
  const { client, base } = openClient(address)
  try {
    const cookie = await authenticate(client, base)
    const value = await rpc(client, cookie, 'session/list', { _request: {} })
    const items = value?.items ?? []
    return items.slice(0, limit).map((item) => {
      // 会话名在 projections.values.title 里，不是顶层字段。
      // DSH 的 title 是自动从首条消息生成的，通常就是用户当时的原话。
      const title = item?.projections?.values?.title
      return {
        sessionId: String(item.sessionId ?? ''),
        title: typeof title === 'string' && title.trim() ? title.trim().slice(0, 80) : null,
        updatedAt: Number(item.updatedAt ?? 0),
        running: Boolean(item.running),
        cwd: item.cwd ? String(item.cwd) : null,
      }
    }).filter((s) => s.sessionId)
  } finally {
    try { client.close() } catch { /* 已关闭 */ }
  }
}

/** 读一次会话尾部，取最后一条助手文本 */
async function lastReply(client, cookie, sessionId) {
  const value = await rpc(client, cookie, 'session/page', {
    request: { address: { kind: 'session', sessionId }, maxMessages: 6 },
  })
  const records = value?.records ?? []
  let reply = ''
  let done = false
  for (const record of records) {
    const ev = record?.event
    if (!ev) continue
    if (ev.type === 'assistant/message') {
      const blocks = ev?.data?.message?.content ?? []
      const text = blocks.filter((b) => b?.type === 'text').map((b) => b.text).join('\n').trim()
      if (text) reply = text
    }
    if (ev.type === 'turn/end') done = true
  }
  return { reply, done }
}

/**
 * 向对方某个会话发一条消息，等回复。
 * 只等「本轮结束」才算完整：一条回复可能分多段发出（工具调用之间还会插入）。
 */
export async function sayToPeer(address, { sessionId, text, timeoutMs = 120000 }) {
  if (!sessionId) throw new Error('缺少目标会话')
  if (!String(text ?? '').trim()) throw new Error('内容为空')

  const { client, base } = openClient(address)
  const started = Date.now()
  try {
    const cookie = await authenticate(client, base)

    await rpc(client, cookie, 'session/prompt', {
      request: {
        requestId: crypto.randomUUID(),
        sessionId,
        mode: 'queue',
        content: [{ type: 'text', text }],
        clientTimeZone: 'Asia/Shanghai',
      },
    })

    let reply = ''
    while (Date.now() - started < timeoutMs) {
      await new Promise((r) => setTimeout(r, 4000))
      try {
        const state = await lastReply(client, cookie, sessionId)
        if (state.reply) reply = state.reply
        if (reply && state.done) break
      } catch { /* 读失败就继续等 */ }
    }
    return { reply, elapsedMs: Date.now() - started }
  } finally {
    try { client.close() } catch { /* 已关闭 */ }
  }
}
