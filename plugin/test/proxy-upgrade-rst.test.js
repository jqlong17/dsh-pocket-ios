import test from 'node:test'
import assert from 'node:assert/strict'
import { createServer, request as httpRequest } from 'node:http'
import { connect } from 'node:net'
import { once } from 'node:events'

/** 起一个 server 并返回端口。 */
function listen(server) {
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server.address().port)))
}

/**
 * 复现线上崩溃：WebSocket(upgrade) 建立后，客户端 RST 断开。
 *
 * 线上症状：手机切后台 / 换网 / 切连接方式 → 对端 RST → 代理里那个裸 socket
 * 读操作抛 ECONNRESET → 没有 'error' 监听 → 冒泡成 uncaughtException →
 * DSH 的 installFailLoud 直接 process.exit(1)。
 *
 * 本用例断言：**带 error 监听的代理不会产生未捕获异常**。
 * 对照组（把两行 socket.on('error') 去掉）会稳定触发 uncaughtException，
 * 所以这个测试能真正防止回归，而不是只做静态断言。
 */
test('upgrade 后客户端 RST，代理不产生未捕获异常', async () => {
  // 上游：接受 upgrade，模拟 DSH 的 WebSocket 端点
  const upstream = createServer()
  upstream.on('upgrade', (req, socket) => {
    socket.on('error', () => { /* 上游自己也要接管 */ })
    socket.write(
      'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n'
    )
  })
  const upstreamPort = await listen(upstream)

  // 代理：与 lib/index.js 的 upgrade 分支保持同一套 error 处理
  const proxy = createServer()
  proxy.on('upgrade', (req, socket, head) => {
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
        if (head?.length) proxySocket.write(head)
      } catch { /* 交给 error 监听 */ }
      proxySocket.pipe(socket)
      socket.pipe(proxySocket)
    })
    proxyReq.on('error', () => socket.destroy())
    proxyReq.end()
  })
  const proxyPort = await listen(proxy)

  // 捕获任何未捕获异常——线上正是它把 host 打死的
  const uncaught = []
  const onUncaught = (err) => uncaught.push(err)
  process.on('uncaughtException', onUncaught)

  try {
    const client = connect(proxyPort, '127.0.0.1')
    client.on('error', () => { /* 客户端自己 RST，忽略自身错误 */ })
    client.write(
      'GET /ws HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n'
    )
    await once(client, 'data')

    // 关键动作：发 RST（不是优雅 close）
    client.resetAndDestroy()
    await new Promise((r) => setTimeout(r, 300))

    assert.equal(uncaught.length, 0, `RST 不该产生未捕获异常，实际收到: ${uncaught.map((e) => e?.code ?? e)}`)
  } finally {
    process.off('uncaughtException', onUncaught)
    // 先断开残余连接再 close：客户端 RST 之后 pipe 的对端 socket 可能还开着，
    // close() 会一直等它们——表现为「测试跑完但进程不退出」（实测）。
    upstream.closeAllConnections?.()
    proxy.closeAllConnections?.()
    // 不 await close()：客户端 RST 之后还有 socket 让 close 的回调不触发，
    // 表现是断言都过了、进程却永不退出（实测 25s 超时）。
    // 这里改成显式销毁 + unref，测试结束即释放。
    upstream.closeAllConnections?.()
    proxy.closeAllConnections?.()
    upstream.close()
    proxy.close()
    upstream.unref()
    proxy.unref()
  }
})
