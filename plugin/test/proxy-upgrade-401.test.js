import test from 'node:test'
import assert from 'node:assert/strict'
import { createServer, request as httpRequest } from 'node:http'
import { connect } from 'node:net'

/**
 * 复现并防住：「上游没升级（401）时，代理把请求挂死」。
 *
 * 线上症状：App 的 Live 一直 reconnecting、帧率 0.00/s，
 * 但普通 HTTP 请求完全正常（走的是另一条路径）。
 *
 * 根因：`http.request` 的 `upgrade` 事件**只在服务器返回 101 时触发**。
 * DSH 因为 cookie 过期返回 401 时，走的是 `response` 事件；
 * 代理只监听了 `upgrade` 和 `error`，`response` 没人接 → 请求永远挂着
 * → 客户端等到超时，看到「连上了但 0 字节」。
 *
 * 本文件断言两件事：
 *   1) 带 `response` 处理的代理：客户端能立刻拿到 401，不是超时。
 *   2) 对照组（去掉 `response` 处理）：客户端超时 —— 证明这个测试
 *      真的能捕获该缺陷，而不是写了一个永远为真的断言。
 */

function listen(server) {
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server.address().port)))
}

/** 起一个「收到 upgrade 就返回 401」的上游，模拟 cookie 过期的 DSH。 */
async function unauthorizedUpstream() {
  const upstream = createServer((req, res) => {
    res.writeHead(401, { 'Content-Type': 'text/plain', 'Content-Length': '12' })
    res.end('Unauthorized')
  })
  // 关键：上游不处理 upgrade，让 node 用普通 response 回 401
  const port = await listen(upstream)
  return { upstream, port }
}

/**
 * 起一个代理，`withResponseHandler` 控制是否补 `response` 监听。
 * 其余逻辑与 lib/index.js 的 upgrade 分支保持一致。
 */
async function startProxy(upstreamPort, { withResponseHandler, timeoutMs = 1500 }) {
  const proxy = createServer()
  proxy.on('upgrade', (req, socket) => {
    const proxyReq = httpRequest({
      host: '127.0.0.1', port: upstreamPort, method: req.method,
      path: req.url, headers: req.headers,
    })
    proxyReq.on('upgrade', (proxyRes, proxySocket, proxyHead) => {
      socket.on('error', () => { try { proxySocket.destroy() } catch { /* 已关闭 */ } })
      proxySocket.on('error', () => { try { socket.destroy() } catch { /* 已关闭 */ } })
      const lines = ['HTTP/1.1 101 Switching Protocols']
      for (const [k, v] of Object.entries(proxyRes.headers)) {
        if (v !== undefined) lines.push(`${k}: ${Array.isArray(v) ? v.join(', ') : v}`)
      }
      try {
        socket.write(lines.join('\r\n') + '\r\n\r\n')
        if (proxyHead?.length) socket.write(proxyHead)
      } catch { /* 已断开 */ }
      proxySocket.pipe(socket)
      socket.pipe(proxySocket)
    })
    if (withResponseHandler) {
      proxyReq.on('response', (proxyRes) => {
        proxyRes.on('error', () => { try { socket.destroy() } catch { /* 已关闭 */ } })
        const headers = [`HTTP/1.1 ${proxyRes.statusCode} ${proxyRes.statusMessage ?? ''}`]
        for (const [k, v] of Object.entries(proxyRes.headers)) {
          if (v !== undefined) headers.push(`${k}: ${Array.isArray(v) ? v.join(', ') : v}`)
        }
        try { socket.write(headers.join('\r\n') + '\r\n\r\n') } catch { /* 已断开 */ }
        proxyRes.pipe(socket)
      })
    }
    proxyReq.on('error', () => socket.destroy())
    proxyReq.end()
    // 模拟线上客户端的耐心：到点还没响应就算超时
    setTimeout(() => { try { socket.destroy() } catch { /* 已关闭 */ } }, timeoutMs).unref()
  })
  const port = await listen(proxy)
  return { proxy, port }
}

/** 对代理发一次 upgrade 请求，返回收到的第一行状态或 'timeout'。 */
function upgradeOnce(port, timeoutMs = 800) {
  return new Promise((resolve) => {
    const socket = connect(port, '127.0.0.1')
    let buffer = ''
    let done = false
    const finish = (value) => {
      if (done) return
      done = true
      try { socket.destroy() } catch { /* 已关闭 */ }
      resolve(value)
    }
    const timer = setTimeout(() => finish('timeout'), timeoutMs)
    socket.on('connect', () => {
      socket.write(
        'GET /api/remote.mux HTTP/1.1\r\n' +
        'Host: 127.0.0.1\r\n' +
        'Connection: Upgrade\r\n' +
        'Upgrade: websocket\r\n' +
        'Sec-WebSocket-Version: 13\r\n' +
        'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n'
      )
    })
    socket.on('data', (chunk) => {
      buffer += chunk.toString('utf8')
      const line = buffer.split('\r\n')[0]
      if (line) {
        clearTimeout(timer)
        finish(line)
      }
    })
    socket.on('error', () => { clearTimeout(timer); finish('error') })
    socket.on('close', () => { clearTimeout(timer); finish('closed') })
  })
}

test('上游 401 时，带 response 处理的代理立刻回 401', async () => {
  const { upstream, port: up } = await unauthorizedUpstream()
  const { proxy, port: px } = await startProxy(up, { withResponseHandler: true })
  try {
    const line = await upgradeOnce(px)
    assert.match(line, /401/, `应当收到 401，实际是：${line}`)
  } finally {
    proxy.close()
    upstream.close()
  }
})

test('上游 401 时，缺 response 处理的代理会挂到超时（对照组）', async () => {
  const { upstream, port: up } = await unauthorizedUpstream()
  const { proxy, port: px } = await startProxy(up, { withResponseHandler: false, timeoutMs: 600 })
  try {
    const line = await upgradeOnce(px, 500)
    assert.equal(line, 'timeout', `对照组的期望是超时，实际是：${line}`)
  } finally {
    proxy.close()
    upstream.close()
  }
})

test('上游 101 时正常透传（防止修复破坏正常路径）', async () => {
  const upstream = createServer()
  upstream.on('upgrade', (req, socket) => {
    socket.on('error', () => { /* 上游接管 */ })
    socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n')
  })
  const up = await listen(upstream)
  const { proxy, port: px } = await startProxy(up, { withResponseHandler: true })
  try {
    const line = await upgradeOnce(px)
    assert.match(line, /101/, `应当收到 101，实际是：${line}`)
  } finally {
    proxy.close()
    upstream.close()
  }
})
