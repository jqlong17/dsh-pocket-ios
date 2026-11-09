/**
 * dsh-pocket-ios 宿主入口。
 * 1) 检测本机 Tailscale（DNSName + tailscale serve 的 HTTPS 地址）；
 * 2) 读取 dsh-pocket 的访问密码，生成带 `?pin=` 的二维码（App 扫码即连）；
 * 3) 通过 webServer 暴露 `/dsh-pocket-ios/tailscale.status` 给设置页卡片。
 */
import { appendFile, mkdir, readFile } from 'node:fs/promises'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import QRCode from 'qrcode'

const execFileP = promisify(execFile)

export const name = 'dsh-pocket-ios'
export const inject = ['connection', 'webServer']

const CHANNEL = '/dsh-pocket-ios'
const TAILSCALE_BIN = '/Applications/Tailscale.app/Contents/MacOS/Tailscale'
const BODY_MAX = 64 * 1024

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

async function readPin() {
  for (const file of ['token-lan', 'token']) {
    try {
      const value = (await readFile(join(homedir(), '.dsh', 'dsh-pocket', file), 'utf8')).trim()
      if (value) return value
    } catch { /* 文件不存在时继续尝试下一个 */ }
  }
  return null
}

/** 供 RPC 与单测使用：返回 Tailscale 连接信息与带访问密码的二维码。 */
export async function tailscaleStatus() {
  let dnsName = null
  let httpsUrl = null
  let serveRaw = null
  try {
    const json = JSON.parse(await tailscale(['status', '--json']))
    dnsName = json?.Self?.DNSName ? String(json.Self.DNSName).replace(/\.$/, '') : null
  } catch { /* Tailscale 未安装/未登录 */ }
  try {
    const out = await tailscale(['serve', 'status'])
    serveRaw = out
    const match = out.match(/https:\/\/[^\s)]+/)
    if (match) httpsUrl = match[0].replace(/\/$/, '')
    else await logLine(`serve status 无 https 匹配: ${JSON.stringify(out.slice(0, 200))}`)
  } catch (error) {
    await logLine(`serve status 异常: ${error?.message ?? error}`)
  }

  const pin = await readPin()
  const qrUrl = httpsUrl && pin ? `${httpsUrl}?pin=${encodeURIComponent(pin)}` : httpsUrl
  const qr = qrUrl ? await QRCode.toDataURL(qrUrl, { margin: 1, width: 360 }) : null
  return { available: Boolean(dnsName), dnsName, httpsUrl, pinSet: Boolean(pin), qrUrl, qr, serveRaw }
}

function endpointFromPath(pathname) {
  if (typeof pathname !== 'string' || !pathname.startsWith(`${CHANNEL}/`)) return undefined
  const endpoint = pathname.slice(CHANNEL.length + 1)
  if (!endpoint || endpoint.split('/').some((seg) => seg === '' || seg === '.' || seg === '..')) return undefined
  return endpoint
}

async function readBody(req) {
  const chunks = []
  let size = 0
  for await (const chunk of req) {
    size += chunk.length
    if (size > BODY_MAX) throw new Error('body too large')
    chunks.push(chunk)
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'))
}

function send(res, status, payload) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8' })
  res.end(JSON.stringify(payload))
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
        if (typeof connection?.requestRejection === 'function') {
          const rejection = connection.requestRejection(req)
          if (rejection !== undefined) {
            send(res, rejection, { ok: false })
            return
          }
        }
        const endpoint = endpointFromPath(new URL(req.url ?? '/', 'http://127.0.0.1').pathname)
        if (req.method !== 'POST' || endpoint === undefined) {
          send(res, 404, { ok: false })
          return
        }
        const body = await readBody(req)
        const rpcId = typeof body?.rpcId === 'string' ? body.rpcId : ''
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
}
