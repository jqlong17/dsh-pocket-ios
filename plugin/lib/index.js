/**
 * dsh-pocket-ios 宿主入口。
 * 1) 检测本机 Tailscale（DNSName + tailscale serve 的 HTTPS 地址）；
 * 2) 读取 dsh-pocket 的访问密码，生成带 `?pin=` 的二维码（App 扫码即连）；
 * 3) 通过 webServer 暴露 `/dsh-pocket-ios/tailscale.status` 给设置页卡片。
 */
import { appendFile, mkdir, readFile, writeFile } from 'node:fs/promises'
import { randomInt } from 'node:crypto'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { execFile } from 'node:child_process'
import { createServer, request as httpRequest } from 'node:http'
import { promisify } from 'node:util'
import QRCode from 'qrcode'

const execFileP = promisify(execFile)

export const name = 'dsh-pocket-ios'
export const inject = ['connection', 'webServer']

const CHANNEL = '/dsh-pocket-ios'
const TAILSCALE_BIN = '/Applications/Tailscale.app/Contents/MacOS/Tailscale'
const BODY_MAX = 64 * 1024
/** 稳定本地入口端口：Tailscale Serve 指向它；默认 3081（与 dsh-pocket 代理端口一致）。 */
const PROXY_PORT = Number(process.env.DSH_POCKET_IOS_PROXY_PORT ?? 3081)

const LOG_DIR = join(homedir(), '.dsh', 'dsh-pocket-ios')
async function logLine(line) {
  try {
    await mkdir(LOG_DIR, { recursive: true })
    await appendFile(join(LOG_DIR, 'tailscale.log'), `${new Date().toISOString()} ${line}\n`)
  } catch { /* 日志失败不影响主流程 */ }
}

async function tailscale(args) {
  try {
    const { stdout } = await execFileP(TAILSCALE_BIN, args, { timeout: 8000, maxBuffer: 1 << 20 })
    return stdout
  } catch (error) {
    await logLine(`exec ${args.join(' ')} failed: ${error?.code ?? ''} ${error?.message ?? error}`)
    throw error
  }
}

const PIN_FILE = join(LOG_DIR, 'pin')

/** 读取（或首次生成）本插件自己的访问密码，不依赖 dsh-pocket。 */
const PIN_PATTERN = /^[A-Za-z0-9]{8,64}$/

/** 写入访问密码（自定义或随机刷新）；返回写入后的状态。 */
async function setPin(nextPin) {
  await mkdir(LOG_DIR, { recursive: true })
  await writeFile(PIN_FILE, nextPin, { mode: 0o600 })
}

async function readPin() {
  try {
    const existing = (await readFile(PIN_FILE, 'utf8')).trim()
    if (/^[A-Za-z0-9]{8,64}$/.test(existing)) return existing
  } catch { /* 首次运行：下面生成 */ }
  const pin = String(randomInt(10_000_000, 100_000_000))
  try {
    await mkdir(LOG_DIR, { recursive: true })
    await writeFile(PIN_FILE, pin, { mode: 0o600 })
  } catch { /* 写失败仍返回内存值 */ }
  return pin
}

/** 读取配置文件里的 Tailscale 地址（DSH 宿主进程往往访问不到 Tailscale GUI 的 IPC，
 *  CLI 探测会报 "The Tailscale GUI failed to start"，因此配置文件是首选的可靠来源）。
 * 文件：~/.dsh/dsh-pocket-ios/tailscale.json，内容 {"url":"https://<机器>.<tailnet>.ts.net"}
 */
async function readConfiguredUrl() {
  try {
    const raw = await readFile(join(LOG_DIR, 'tailscale.json'), 'utf8')
    const parsed = JSON.parse(raw)
    const url = typeof parsed?.url === 'string' ? parsed.url.trim().replace(/\/$/, '') : ''
    if (/^https:\/\//.test(url)) return url
  } catch { /* 没有配置文件时回退到 CLI */ }
  return null
}

/** 供 RPC 与单测使用：返回 Tailscale 连接信息与带访问密码的二维码。 */
export async function tailscaleStatus() {
  let dnsName = null
  let httpsUrl = null
  let serveRaw = null
  let source = null

  const configuredUrl = await readConfiguredUrl()
  if (configuredUrl) {
    httpsUrl = configuredUrl
    source = 'config'
    try {
      const json = JSON.parse(await tailscale(['status', '--json']))
      dnsName = json?.Self?.DNSName ? String(json.Self.DNSName).replace(/\.$/, '') : null
    } catch { /* 只用于展示；配置了 URL 就够用 */ }
    if (!dnsName) dnsName = new URL(configuredUrl).hostname
  }

  if (!httpsUrl) {
    try {
      const json = JSON.parse(await tailscale(['status', '--json']))
      dnsName = json?.Self?.DNSName ? String(json.Self.DNSName).replace(/\.$/, '') : null
    } catch { /* Tailscale 未安装/未登录 */ }
    try {
      const out = await tailscale(['serve', 'status'])
      serveRaw = out
      const match = out.match(/https:\/\/[^\s)]+/)
      if (match) {
        httpsUrl = match[0].replace(/\/$/, '')
        source = 'cli'
      } else {
        await logLine(`serve status 无 https 匹配: ${JSON.stringify(out.slice(0, 200))}`)
      }
    } catch (error) {
      await logLine(`serve status 异常: ${error?.message ?? error}`)
    }
  }

  const pin = await readPin()
  // 产品安全：二维码只包含连接地址，绝不把访问密码写进二维码/图片。
  const qrUrl = httpsUrl
  const qr = qrUrl ? await QRCode.toDataURL(qrUrl, { margin: 1, width: 360 }) : null
  return { available: Boolean(dnsName) || Boolean(httpsUrl), dnsName, httpsUrl, pin, pinSet: Boolean(pin), qrUrl, qr, serveRaw, source }
}

function endpointFromPath(pathname) {
  if (typeof pathname !== 'string' || !pathname.startsWith(`${CHANNEL}/`)) return undefined
  const endpoint = pathname.slice(CHANNEL.length + 1)
  if (!endpoint || endpoint.split('/').some((seg) => seg === '' || seg === '.' || seg === '..')) return undefined
  return endpoint
}

async function readRawBody(req) {
  const chunks = []
  let size = 0
  for await (const chunk of req) {
    size += chunk.length
    if (size > BODY_MAX) throw new Error('body too large')
    chunks.push(chunk)
  }
  return Buffer.concat(chunks).toString('utf8')
}

async function readBody(req) {
  return JSON.parse(await readRawBody(req))
}

function send(res, status, payload) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8' })
  res.end(JSON.stringify(payload))
}


/**
 * 稳定本地入口：HTTP/WS 代理到当前 DSH web 端口（端口每次重启可能变化）。
 * 外部 Tailscale HTTPS 只需固定指向本端口，不依赖 dsh-pocket。
 */
function attachStableProxy(ctx, handler) {
  const dshPort = ctx.webServer?.port
  if (!dshPort) {
    ctx?.logger?.warn?.('dsh-pocket-ios: 拿不到 DSH web 端口，稳定入口未启动')
    return () => {}
  }
  // DSH 的 browser-auth/可信 Host 校验只认 loopback：Tailscale 进来的公网 Host 必须改写，
  // 否则 token 换完 cookie 后继续访问仍会 403（dsh-pocket 的代理同样做这件事）。
  const forwardHeaders = (headers) => {
    const copy = { ...headers }
    copy.host = `127.0.0.1:${dshPort}`
    if (typeof copy.origin === 'string') copy.origin = `http://127.0.0.1:${dshPort}`
    if (typeof copy.referer === 'string') {
      try {
        const referer = new URL(copy.referer)
        copy.referer = `http://127.0.0.1:${dshPort}${referer.pathname}${referer.search}`
      } catch { /* 非法 Referer 直接丢弃 */ }
    }
    delete copy['x-forwarded-for']
    delete copy['x-forwarded-host']
    delete copy['x-forwarded-proto']
    return copy
  }
  const server = createServer((req, res) => {
    try {
      if ((req.url ?? '').startsWith(`${CHANNEL}/`)) {
        handler(req, res)
        return
      }
      const proxyReq = httpRequest({
        host: '127.0.0.1', port: dshPort, method: req.method,
        path: req.url, headers: forwardHeaders(req.headers),
      }, (proxyRes) => {
        res.writeHead(proxyRes.statusCode ?? 502, proxyRes.headers)
        proxyRes.pipe(res)
      })
      proxyReq.on('error', () => {
        try { res.writeHead(502, { 'content-type': 'text/plain' }); res.end('bad gateway') } catch { /* 已结束 */ }
      })
      req.pipe(proxyReq)
    } catch {
      try { res.writeHead(502); res.end() } catch { /* 已结束 */ }
    }
  })
  server.on('upgrade', (req, socket, head) => {
    const proxyReq = httpRequest({
      host: '127.0.0.1', port: dshPort, method: req.method,
      path: req.url, headers: forwardHeaders(req.headers),
    })
    proxyReq.on('upgrade', (proxyRes, proxySocket, proxyHead) => {
      const lines = [`HTTP/1.1 101 Switching Protocols`]
      for (const [key, value] of Object.entries(proxyRes.headers)) {
        if (value !== undefined) lines.push(`${key}: ${Array.isArray(value) ? value.join(', ') : value}`)
      }
      socket.write(lines.join('\r\n') + '\r\n\r\n')
      if (proxyHead?.length) socket.write(proxyHead)
      if (head?.length) proxySocket.write(head)
      proxySocket.pipe(socket)
      socket.pipe(proxySocket)
    })
    proxyReq.on('error', () => socket.destroy())
    proxyReq.end()
  })
  server.on('error', (error) => ctx?.logger?.warn?.(`dsh-pocket-ios: 稳定入口端口 ${PROXY_PORT} 不可用（${error?.message ?? error}）`))
  server.listen(PROXY_PORT, '127.0.0.1', () => {
    ctx?.logger?.info?.(`dsh-pocket-ios: 稳定入口 http://127.0.0.1:${PROXY_PORT} → DSH ${dshPort}`)
  })
  return () => { try { server.close() } catch { /* 已关闭 */ } }
}

/**
 * 挂载 RPC 路由。auth 用 connection.requestRejection（必须绑定 this，否则丢失 trustedHosts）。
 * @param ctx - cordis 插件上下文。
 */
export function apply(ctx) {
  const webServer = ctx?.webServer
  const connection = ctx?.connection
  if (!webServer || typeof webServer.register !== 'function') {
    ctx?.logger?.warn?.('dsh-pocket-ios: webServer 不可用，Tailscale 卡片 RPC 未挂载')
    return
  }
  const route = {
    kind: 'prefix',
    path: CHANNEL,
    handler: async (req, res) => {
      try {
        const rawPath = new URL(req.url ?? '/', 'http://127.0.0.1').pathname
        const isLogin = rawPath === `${CHANNEL}/login`
        if (!isLogin && typeof connection?.requestRejection === 'function') {
          const rejection = connection.requestRejection(req)
          if (rejection !== undefined) {
            send(res, rejection, { ok: false })
            return
          }
        }
        const urlObject = new URL(req.url ?? '/', 'http://127.0.0.1')
        const endpoint = endpointFromPath(urlObject.pathname)
        if (endpoint === undefined) {
          send(res, 404, { ok: false })
          return
        }
        // 登录端点：不需要已有浏览器会话，用本插件自己的 PIN 换 DSH 的认证 cookie。
        if (endpoint === 'login') {
          if (req.method !== 'POST' && req.method !== 'GET') { send(res, 405, { ok: false }); return }
          let pinAttempt = urlObject.searchParams.get('token') ?? ''
          if (req.method === 'POST') {
            const raw = await readRawBody(req)
            const contentType = String(req.headers['content-type'] ?? '')
            if (contentType.includes('application/json')) {
              try {
                const body = JSON.parse(raw)
                pinAttempt = body?.token ?? body?.pin ?? pinAttempt
              } catch { /* 非法 JSON 按未提供处理 */ }
            } else {
              pinAttempt = new URLSearchParams(raw).get('token') ?? pinAttempt
            }
          }
          const expected = await readPin()
          const attempt = String(pinAttempt ?? '')
          if (attempt !== expected) {
            await logLine(`login 401 host=${String(req.headers.host ?? '')} attemptLen=${attempt.length}`)
            send(res, 401, { ok: false })
            return
          }
          // 重定向必须回到“客户端正在使用的地址”（localhost / 局域网 / Tailscale 都可），
          // 不能固定用配置里的 Tailscale 地址，否则局域网登录会被带到不可达的域名。
          const host = String(req.headers.host ?? '')
          if (!host || typeof connection?.authenticatedUrl !== 'function') {
            send(res, 503, { ok: false })
            return
          }
          const forwardedProto = String(req.headers['x-forwarded-proto'] ?? '').split(',')[0].trim()
          const isLoopback = /^(127\.0\.0\.1|localhost|\[::1\])(:\d+)?$/i.test(host)
          const proto = forwardedProto || (isLoopback ? 'http' : 'https')
          const target = connection.authenticatedUrl(`${proto}://${host}/`)
          res.writeHead(302, { location: target, 'cache-control': 'no-store' })
          res.end()
          return
        }
        if (req.method !== 'POST') {
          send(res, 404, { ok: false })
          return
        }
        const body = await readBody(req)
        const rpcId = typeof body?.rpcId === 'string' ? body.rpcId : ''
        if (endpoint === 'pin.refresh') {
          const nextPin = String(randomInt(10_000_000, 100_000_000))
          await setPin(nextPin)
          await logLine('pin refreshed')
          const value = await tailscaleStatus()
          send(res, 200, { type: 'server-response', rpcId, result: { ok: true, value } })
          return
        }
        if (endpoint === 'pin.set') {
          const args = body?.payload?.args ?? body?.payload ?? body?.args ?? body ?? {}
          const requested = String(args.pin ?? '')
          if (!PIN_PATTERN.test(requested)) {
            send(res, 200, { type: 'server-response', rpcId, result: { ok: false, error: { code: 'bad-request', message: '密码需为 8-64 位英文字母或数字' } } })
            return
          }
          await setPin(requested)
          await logLine('pin set by user')
          const value = await tailscaleStatus()
          send(res, 200, { type: 'server-response', rpcId, result: { ok: true, value } })
          return
        }
        if (endpoint !== 'tailscale.status') {
          send(res, 200, { type: 'server-response', rpcId, result: { ok: false, error: { code: 'bad-request', message: `unknown endpoint ${endpoint}` } } })
          return
        }
        const value = await tailscaleStatus()
        send(res, 200, { type: 'server-response', rpcId, result: { ok: true, value } })
      } catch (error) {
        send(res, 200, { type: 'server-response', rpcId: '', result: { ok: false, error: { code: 'bad-request', message: String(error?.message ?? error) } } })
      }
    },
  }
  try {
    webServer.register(route)
    ctx?.logger?.info?.('dsh-pocket-ios: Tailscale RPC 已挂载 /dsh-pocket-ios/tailscale.status')
  } catch (error) {
    ctx?.logger?.warn?.(`dsh-pocket-ios: 挂载 RPC 失败：${String(error?.message ?? error)}`)
  }
  return attachStableProxy(ctx, route.handler)
}
