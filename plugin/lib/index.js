/**
 * dsh-pocket-ios 宿主入口。
 *
 * 与 dsh-pocket **无依赖**：连接、密码、配对全都自己实现。
 * 1) 四种连接方式（lan / cloudflare / tailscale / easytier）各自探测本机地址；
 * 2) 访问密码由本插件生成并保存在 ~/.dsh/dsh-pocket-ios/pin（不回退读第三方插件）；
 * 3) 扫码建连走一次性 token：`?pair=<token>` → POST /dsh-pocket-ios/pair 换 dsh-auth cookie；
 * 4) 通过 webServer 暴露 `/dsh-pocket-ios/*` 给设置页卡片与 App。
 */
import { appendFile, mkdir, readFile, readdir, writeFile } from 'node:fs/promises'
import { shouldNotify, lastAssistantSnippet } from './push-scan.js'
import { ProviderTokenCache, sendPush } from './apns.js'
import { listActiveSessionFiles, readTailEvents } from './session-tail.js'
import { snapshotFromTelemetry, messageDescriptor, buildTag, isSnapshotFresh } from './connection-tags.js'
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { createRequire } from 'node:module'
import { randomInt } from 'node:crypto'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { execFile } from 'node:child_process'
import { createServer, request as httpRequest } from 'node:http'
import { promisify } from 'node:util'
import QRCode from 'qrcode'
import { CloudflareTunnel, findCloudflared } from './cloudflare.js'
import { selectLanIPv4, lanEntryUrl } from './lan.js'
import { findEasytier, readWireGuardPortal, normalizeWireGuardConfig, clientAddressFrom, coreCommand, randomNetwork, shadowrocketConf, installServiceCommand, uninstallServiceCommand, EASYTIER_DAEMON_LABEL } from './easytier.js'

const execFileP = promisify(execFile)

export const name = 'dsh-pocket-ios'
export const inject = ['connection', 'webServer']

const CHANNEL = '/dsh-pocket-ios'

/**
 * 插件移动端聚合通道。
 *
 * **为什么放在这个插件里而不是 dsh-plugin-panel**：
 * 这个插件是用户装了 App 就**必须**装的那一个（它开 3091 代理、管 PIN 和配对），
 * 而插件管理是选装包——App Store 用户按安装文档只会装这一个，
 * 把聚合能力放在选装包里，等于让「插件」按钮对默认用户不可用（2026-11-16 确认）。
 *
 * DSH 内核没有对外的插件列表 API（`/plugins/*` 只是 client 资源路由），
 * 所以这个能力只能由插件提供，放这里最合适：token 签发本来就该和 PIN/配对在一起。
 */
const PLUGIN_CHANNEL = '/dsh-pocket/plugins'
/** 移动端一次性 token 的有效期，和 dsh-plugin-panel 保持一致。 */
const MOBILE_TOKEN_TTL_MS = 5 * 60 * 1000
/** token 形状：32 位 base64url。别的插件签的也长这样，所以只用来验格式。 */
const MOBILE_TOKEN_RE = /^[A-Za-z0-9_-]{32}$/
/** 本插件签发的 token → 过期时间。只校验自己签的，别处的 token 无从校验。 */
const mobileTokens = new Map()
/** 换 token 的限流桶：IP → 最近一分钟的时间戳。 */
const mobileMintBuckets = new Map()

/**
 * token 端点的限流：每 IP 每分钟 10 次。
 *
 * **这个端点不能做 DSH 的 Host 校验**：手机走的是局域网/Tailscale 的 Host，
 * `connection.requestRejection` 一律拒绝（它只信任 loopback / trustedHosts）。
 * 2026-11-16 我先写了 requestRejection，结果手机端永远拿不到 token——
 * 和最早 `dsh-plugin-panel` 踩的是同一个坑。
 *
 * 安全性靠「限流 + token 短期 + 只读数据」兜底：token 只用于列插件（不含凭证），
 * 5 分钟过期、只存内存。
 */
function allowMobileMint(req) {
  const ip = String(req.socket?.remoteAddress ?? 'unknown')
  const now = Date.now()
  const windowStart = now - 60_000
  const hits = (mobileMintBuckets.get(ip) ?? []).filter((t) => t > windowStart)
  if (hits.length >= 10) {
    mobileMintBuckets.set(ip, hits)
    return false
  }
  hits.push(now)
  mobileMintBuckets.set(ip, hits)
  if (mobileMintBuckets.size > 64) {
    for (const [key, list] of mobileMintBuckets) {
      if (list.every((t) => t <= windowStart)) mobileMintBuckets.delete(key)
    }
  }
  return true
}
/**
 * EasyTier WireGuard 门户端口。
 * **不能落在 11010–11013**：EasyTier 默认已在那几个端口上监听
 * tcp/udp/wg/quic/ws/wss/faketcp，实测复用会 "Address already in use"。
 */
const EASYTIER_PORTAL_PORT = 11500
/** EasyTier 的 SOCKS5 端口（--socks5 的参数）。 */
const EASYTIER_SOCKS_PORT = 1080
/** WireGuard / 代理客户端用的虚拟网段，与 --vpn-portal 的路径段一致。 */
const EASYTIER_CLIENT_CIDR = '10.14.14.0/24'
// Tailscale 可执行文件的位置。
// macOS 上 DSH 进程拿不到 Tailscale GUI 的 IPC，必须用 App 内置的 CLI；
// Linux（包括云服务器）上则是 PATH 里的 /usr/bin/tailscale。
// 之前写死 macOS 路径，导致服务器上每个 tailscale 调用都 ENOENT、
// 插件判定「当前连接方式还没有地址」（2026-11-15 在阿里云上踩到）。
const TAILSCALE_BIN = process.platform === 'darwin'
  ? '/Applications/Tailscale.app/Contents/MacOS/Tailscale'
  : 'tailscale'
const BODY_MAX = 64 * 1024
/** 稳定本地入口端口：Tailscale Serve 指向它；默认 3081（与 dsh-pocket 代理端口一致）。 */
const PROXY_PORT = Number(process.env.DSH_POCKET_IOS_PROXY_PORT ?? 3091)

const LOG_DIR = join(homedir(), '.dsh', 'dsh-pocket-ios')

// 一次性配对 token 有效期。10 分钟：手机端要经历「看到码 → 掏出手机 →
// 从相册选图 / 对准扫码 → 等隧道冷启动」，实测 5 分钟在服务器 + 相册导入
// 这种慢路径下经常刚好过期（用户反馈）。
const PAIR_TTL_MS = 600_000

// 一次性配对 token，用于扫码免密码连接。
const pairTokens = new Map()

/**
 * 生成一个配对 token（32 字符 base64url 字符集）。
 *
 * 抽成公共函数是因为 CLI 端点（cli.pair）最初写了 `newPairToken()` 这个
 * 不存在的名字，运行时才报 "newPairToken is not defined"——静态检查发现不了。
 * 两处共用一份实现，杜绝这种漂移。
 */
function generatePairToken() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'
  return Array.from({ length: 32 }, () => chars[Math.floor(Math.random() * chars.length)]).join('')
}

// ── 插件移动端聚合 ───────────────────────────────────────────────────

/** 签发一个移动端 token（5 分钟）。顺手清过期的，避免 Map 无限增长。 */
function mintMobileToken() {
  const token = generatePairToken()
  const now = Date.now()
  for (const [key, expiresAt] of mobileTokens) if (expiresAt < now) mobileTokens.delete(key)
  mobileTokens.set(token, now + MOBILE_TOKEN_TTL_MS)
  return token
}

/**
 * 只认**本插件签发**的 token。
 *
 * 为什么不像插件页面那样只验格式：这里是发 token 的一方，
 * 必须能拒绝伪造/过期的。插件页面（比如音频解析）收到的是我们签的 token，
 * 它们只验格式是合理的——它们无从校验别处的签发记录。
 */
function mobileTokenValid(token) {
  if (typeof token !== 'string' || token.length !== 32) return false
  const expiresAt = mobileTokens.get(token)
  if (expiresAt === undefined) return false
  if (expiresAt < Date.now()) {
    mobileTokens.delete(token)
    return false
  }
  return true
}

const bundleRequire = createRequire(import.meta.url)

/**
 * 可能的 node_modules 根，按可靠性排序。
 *
 * 为什么要扫 profile：插件常常是**指向源码目录的符号链接**，
 * `import.meta.url` 解析到的是源码目录，从它推不出 DSH 装包的位置。
 */
function packageRoots() {
  const roots = []
  try {
    let dir = dirname(fileURLToPath(import.meta.url))
    for (let i = 0; i < 8; i += 1) {
      if (dir.endsWith('node_modules')) {
        roots.push(dir)
        break
      }
      const parent = dirname(dir)
      if (parent === dir) break
      dir = parent
    }
  } catch { /* 推不出来就走 profiles */ }

  const profilesRoot = join(homedir(), '.dsh', 'profiles')
  try {
    for (const entry of readdirSync(profilesRoot, { withFileTypes: true })) {
      if (entry.isDirectory()) roots.push(join(profilesRoot, entry.name, 'node_modules'))
    }
  } catch { /* 没有 profiles 目录 */ }
  return [...new Set(roots)]
}

/** 从包名找包目录：Node 解析链优先，被 exports 挡住时再逐个根去找。 */
function resolvePackageDir(name) {
  try {
    return dirname(bundleRequire.resolve(`${name}/package.json`))
  } catch { /* 被 exports 挡住 */ }
  try {
    let dir = dirname(bundleRequire.resolve(name))
    for (let i = 0; i < 6; i += 1) {
      if (existsSync(join(dir, 'package.json'))) return dir
      const parent = dirname(dir)
      if (parent === dir) break
      dir = parent
    }
  } catch { /* 解析不了 */ }
  for (const root of packageRoots()) {
    const dir = join(root, name)
    if (existsSync(join(dir, 'package.json'))) return dir
  }
  return null
}

/** kind 的合法值（协议 v1）。 */
const MOBILE_KINDS = new Set(['web', 'native'])
/** App 支持的 dsh.mobile 协议版本。 */
const MOBILE_PROTOCOL_VERSION = 1

/**
 * 扫出所有声明了 `dsh.mobile` 的插件。
 *
 * 协议校验规则和 `dsh-plugin-panel` 的实现保持一致——App 两边都能解析，
 * 漂移会让「同一份声明在一处有效、另一处被过滤」。
 *
 * @param pluginManager - DSH 内核的插件管理 service（不是任何第三方插件）。
 * @returns `{ plugins, invalid }`，invalid 带原因，好让 App 说出「哪里不合格」。
 */
async function readMobileManifests(pluginManager) {
  const plugins = []
  const invalid = []
  if (!pluginManager || typeof pluginManager.listBundles !== 'function') return { plugins, invalid }

  let bundles = []
  try {
    bundles = await pluginManager.listBundles()
  } catch {
    return { plugins, invalid }
  }

  for (const bundle of Array.isArray(bundles) ? bundles : []) {
    const moduleName = typeof bundle?.name === 'string' ? bundle.name : ''
    if (!moduleName) continue
    // DSH 自带的包和内核条目不列（和桌面端的面板一致）
    if (moduleName.startsWith('@deepseek-ai/') || moduleName.startsWith('cordis:')) continue

    const dir = resolvePackageDir(moduleName)
    if (dir === null) continue
    let pkg
    try {
      pkg = JSON.parse(readFileSync(join(dir, 'package.json'), 'utf8'))
    } catch { continue }

    const mobile = pkg?.dsh?.mobile
    if (mobile === undefined || mobile === null) continue
    if (typeof mobile !== 'object' || Array.isArray(mobile)) {
      invalid.push({ module: moduleName, title: moduleName, problems: ['dsh.mobile 必须是对象'] })
      continue
    }

    const problems = []
    const version = Number(mobile.version)
    if (!Number.isFinite(version)) problems.push('dsh.mobile.version 缺失')
    else if (version > MOBILE_PROTOCOL_VERSION) {
      problems.push(`dsh.mobile.version=${version} 高于 App 支持的 ${MOBILE_PROTOCOL_VERSION}`)
    }

    const kind = typeof mobile.kind === 'string' ? mobile.kind.trim() : ''
    if (!MOBILE_KINDS.has(kind)) problems.push('dsh.mobile.kind 必须是 web 或 native')

    const title = typeof mobile.title === 'string' ? mobile.title.trim() : ''
    if (title === '') problems.push('dsh.mobile.title 缺失')

    const mobilePath = typeof mobile.path === 'string' ? mobile.path.trim() : ''
    if (kind === 'web') {
      if (mobilePath === '') problems.push('kind=web 但 dsh.mobile.path 缺失')
      else if (!mobilePath.startsWith('/')) problems.push('dsh.mobile.path 必须以 / 开头')
    } else if (kind === 'native') {
      // Schema 渲染器在 App 里还没实现；照实返回，让 App 能给出「需要更新版本」的提示
      const schema = typeof mobile.schema === 'string' ? mobile.schema.trim() : ''
      if (schema === '') problems.push('kind=native 但 dsh.mobile.schema 缺失')
    }

    if (problems.length > 0) {
      invalid.push({ module: moduleName, title: title || moduleName, problems })
      continue
    }
    plugins.push({ module: moduleName, title, version, kind, path: mobilePath })
  }
  return { plugins, invalid }
}

/**
 * 读一个插件的本地化标题和简介。
 *
 * 只取 `locale/*.json` 的 `meta.title` / `meta.description`，回退 `package.json`。
 * 刻意不复刻「长文 detail / README 首段」——原生列表卡片只要一两行简介。
 *
 * 规则和 DSH 启动时一致：`locale/en.json` 是入口，不存在就整个不加载。
 */
function readPluginTexts(dir, acceptLanguage) {
  let fallbackTitle = ''
  let fallbackDescription = ''
  try {
    const pkg = JSON.parse(readFileSync(join(dir, 'package.json'), 'utf8'))
    if (typeof pkg.name === 'string') fallbackTitle = pkg.name.trim()
    if (typeof pkg.description === 'string') fallbackDescription = pkg.description.trim()
  } catch { /* 坏包：全靠 locale */ }

  const dicts = new Map()
  const localeDir = join(dir, 'locale')
  try {
    if (existsSync(join(localeDir, 'en.json'))) {
      for (const entry of readdirSync(localeDir, { withFileTypes: true })) {
        if (!entry.isFile() || !entry.name.endsWith('.json')) continue
        try {
          const dict = JSON.parse(readFileSync(join(localeDir, entry.name), 'utf8'))
          const meta = dict?.meta ?? {}
          dicts.set(entry.name.replace(/\.json$/, ''), {
            title: typeof meta.title === 'string' ? meta.title.trim() : '',
            description: typeof meta.description === 'string' ? meta.description.trim() : '',
          })
        } catch { /* 坏 json 跳过 */ }
      }
    }
  } catch { /* 没有 locale 目录 */ }

  // 手机请求可能带 zh-CN / zh-Hans-CN / en。取到语言主标签再匹配。
  const requested = String(acceptLanguage ?? '').toLowerCase()
  const isEnglish = requested.startsWith('en')
  const zh = dicts.get('zh') || dicts.get('zh-Hans') || {}
  const en = dicts.get('en') || {}
  const chosen = isEnglish ? (en.title ? en : zh) : (zh.title ? zh : en)

  return {
    title: chosen.title || en.title || fallbackTitle,
    description: chosen.description || en.description || fallbackDescription,
  }
}

/**
 * 全部已装插件——原生列表要显示开关，所以**不只是**声明了 mobile 的那些。
 *
 * 字段说明：
 * - `enabled`：来自 `listPlugins()`（`listBundles()` 没有这个字段，别用错）
 * - `mobilePath`：有值才显示「打开」按钮
 */
async function readInstalledPlugins(pluginManager, acceptLanguage) {
  const out = []
  if (!pluginManager || typeof pluginManager.listBundles !== 'function') return out

  let bundles = []
  try {
    bundles = await pluginManager.listBundles()
  } catch {
    return out
  }

  const states = new Map()
  if (typeof pluginManager.listPlugins === 'function') {
    try {
      const list = await pluginManager.listPlugins()
      for (const plugin of Array.isArray(list) ? list : []) {
        const name = plugin?.moduleName || plugin?.name
        if (typeof name !== 'string' || !name) continue
        states.set(name, {
          entryId: typeof plugin.entryId === 'string' ? plugin.entryId : '',
          enabled: plugin.enabled !== false,
          // 配置上启用 ≠ 实际在跑：fiberPhase 才是运行状态。
          fiberPhase: typeof plugin.fiberPhase === 'string' ? plugin.fiberPhase : '',
          diagnostic: typeof plugin.diagnostic === 'string' ? plugin.diagnostic : '',
          // 只读条目（受管理/不可寻址）不能让手机改，交换开会失败。
          readOnlyReason: typeof plugin.readOnlyReason === 'string' ? plugin.readOnlyReason : '',
        })
      }
    } catch { /* 读不到就当作全部启用 */ }
  }

  for (const bundle of Array.isArray(bundles) ? bundles : []) {
    const moduleName = typeof bundle?.name === 'string' ? bundle.name : ''
    if (!moduleName) continue
    // DSH 自带的包不列（和桌面端面板一致）
    if (moduleName.startsWith('@deepseek-ai/') || moduleName.startsWith('cordis:')) continue

    const dir = resolvePackageDir(moduleName)
    if (dir === null) continue

    const texts = readPluginTexts(dir, acceptLanguage)
    let mobilePath = ''
    try {
      const pkg = JSON.parse(readFileSync(join(dir, 'package.json'), 'utf8'))
      const candidate = pkg?.dsh?.mobile?.path
      if (typeof candidate === 'string' && candidate.startsWith('/')) mobilePath = candidate
    } catch { /* 没有声明就没有打开按钮 */ }

    out.push({
      module: moduleName,
      title: texts.title || moduleName,
      version: typeof bundle.version === 'string' ? bundle.version : '',
      description: texts.description,
      // 关键：listBundles 会列出「装了但没启用」的 bundle（此时它不在 listPlugins 里）。
      // 查不到状态 = 这个条目根本没被 Loader 加载 = 未启用。
      // 之前写 `?? true`，把「查不到」当成「启用」，于是列表上所有插件全显示开着。
      enabled: states.get(moduleName)?.enabled ?? false,
      fiberPhase: states.get(moduleName)?.fiberPhase ?? '',
      diagnostic: states.get(moduleName)?.diagnostic ?? '',
      readOnlyReason: states.get(moduleName)?.readOnlyReason ?? '',
      mobilePath,
    })
  }
  return out
}

/**
 * 挂载插件移动端聚合路由。
 *
 * 单独成一个函数、由 apply 用 `ctx.inject(['pluginManager'])` 挂载：
 * `pluginManager` 不可用时只是这个能力不生效，**不能连累主插件**
 * （PIN、配对、代理都在这个插件里）。
 */
export function registerPluginAggregator(ctx) {
  const webServer = ctx?.webServer
  const pluginManager = ctx?.pluginManager
  if (!webServer || typeof webServer.register !== 'function') return () => {}

  return webServer.register({
    kind: 'prefix',
    path: PLUGIN_CHANNEL,
    handler: async (req, res) => {
      const url = new URL(req.url ?? '/', 'http://127.0.0.1')
      const sendJson = (status, payload) => {
        res.writeHead(status, {
          'content-type': 'application/json; charset=utf-8',
          'cache-control': 'no-store',
        })
        res.end(JSON.stringify(payload))
      }

      // ① 换 token：**不做 Host 校验**，靠限流（见 allowMobileMint 的注释）
      if (url.pathname === `${PLUGIN_CHANNEL}/token`) {
        if (req.method !== 'POST') {
          sendJson(405, { ok: false, error: 'method not allowed' })
          return
        }
        if (!allowMobileMint(req)) {
          sendJson(429, { ok: false, error: '请求太频繁，请稍后再试' })
          return
        }
        sendJson(200, {
          token: mintMobileToken(),
          expiresIn: Math.round(MOBILE_TOKEN_TTL_MS / 1000),
        })
        return
      }

      // ② 其余端点只认本插件签发的 token（WebView 带不上 cookie）
      const token = url.searchParams.get('mt')
      if (!mobileTokenValid(token)) {
        sendJson(401, { ok: false, error: '请从 DSH Pocket App 内打开' })
        return
      }

      if (url.pathname === `${PLUGIN_CHANNEL}/list`) {
        const { plugins, invalid } = await readMobileManifests(pluginManager)
        sendJson(200, { version: MOBILE_PROTOCOL_VERSION, plugins, invalid })
        return
      }

      // ③ 原生列表用：全部已装插件（含 enabled），不只是声明了 mobile 的
      if (url.pathname === `${PLUGIN_CHANNEL}/installed`) {
        const plugins = await readInstalledPlugins(pluginManager, req.headers['accept-language'])
        sendJson(200, { version: MOBILE_PROTOCOL_VERSION, plugins })
        return
      }

      // ④ 开关插件。这是**写操作**，所以只在严格校验过 token 之后才走到这里。
      if (url.pathname === `${PLUGIN_CHANNEL}/toggle`) {
        if (req.method !== 'POST') {
          sendJson(405, { ok: false, error: 'method not allowed' })
          return
        }
        let payload = {}
        try {
          // readBody 内部已经 JSON.parse 过了，这里再解析一次会对「对象」调 JSON.parse
          // → 抛错 → 一律返回 bad body。开关因此**永远失败**（App 收到 400 就回滚）。
          payload = (await readBody(req)) ?? {}
        } catch {
          sendJson(400, { ok: false, error: 'bad body' })
          return
        }
        const name = typeof payload.name === 'string' ? payload.name : ''
        const enabled = payload.enabled === true
        if (!name) {
          sendJson(400, { ok: false, error: 'missing name' })
          return
        }
        // **不能关自己**：这个插件就是手机的连接通道（3091 代理 + PIN），
        // 关掉之后 App 直接失联，连把它开回来的入口都没有。
        if (name === 'dsh-pocket-ios' && !enabled) {
          sendJson(409, { ok: false, error: '不能关闭 dsh-pocket-ios 自身：它是手机连接的通道' })
          return
        }
        try {
          let entryId = ''
          if (typeof pluginManager?.listPlugins === 'function') {
            const list = await pluginManager.listPlugins()
            for (const plugin of Array.isArray(list) ? list : []) {
              const moduleName = plugin?.moduleName || plugin?.name
              if (moduleName === name && typeof plugin.entryId === 'string') {
                entryId = plugin.entryId
                break
              }
            }
          }
          // 两种条目要分开处理：
          //   ① 已加载 → 有 entryId，用 setPluginEnabled（条目级）
          //   ② 未加载 → 它所属的 bundle 没被选中，setPluginEnabled 会抛 unknown-plugin，
          //      必须用 setBundleEnabled（bundle 级，会顺手 publish + reload）
          let result
          if (entryId) {
            result = await pluginManager.setPluginEnabled(entryId, enabled)
          } else if (typeof pluginManager.setBundleEnabled === 'function') {
            result = await pluginManager.setBundleEnabled(name, enabled)
          } else {
            sendJson(400, { ok: false, error: '这个插件需要先在电脑端启用' })
            return
          }
          const application = typeof result?.application === 'string' ? result.application : ''
          const restartReason = typeof result?.restartReason === 'string' ? result.restartReason : ''
          const failed = application === 'failed' || application === 'cancelled' || result?.error != null
          sendJson(failed ? 500 : 200, {
            ok: !failed,
            module: name,
            enabled,
            application,
            restartReason,
            // 给 App 一句能直接显示的话（空 = 立即生效，不用提示）
            note: application === 'restart-required'
              ? '已保存，重启 DSH 后生效'
              : application === 'overridden'
                ? '被更高优先级的配置覆盖，未生效'
                : application === 'failed'
                  // 带上具体原因：ManagementError 里是 code + detail 之类，别只报「切换失败」。
                  ? String(result?.error?.message ?? result?.error?.code ?? result?.error ?? '切换失败')
                  : '',
          })
        } catch (error) {
          sendJson(500, { ok: false, error: String(error?.message ?? error) })
        }
        return
      }
      sendJson(404, { ok: false, error: 'not found' })
    },
  })
}

/**
 * 长期设备凭证。
 *
 * 为什么需要：DSH 的 dsh-auth cookie 是 **session 级**的，DSH 一重启就失效，
 * 用户就得重新扫码。设备凭证存在电脑上（不含密码），App 存一份在 Keychain，
 * cookie 失效时用它换新的——除非用户主动撤销设备，否则不必再扫。
 *
 * 存储：~/.dsh/dsh-pocket-ios/devices.json
 *   { "<token>": { name, createdAt, lastUsedAt } }
 * token 是 32 字节随机串，只在本机文件与用户 Keychain 里，不上传任何地方。
 */
const DEVICE_FILE = join(LOG_DIR, 'devices.json')
let devicesCache = null

async function readDevices() {
  if (devicesCache) return devicesCache
  try {
    devicesCache = JSON.parse(await readFile(DEVICE_FILE, 'utf8'))
    if (!devicesCache || typeof devicesCache !== 'object') devicesCache = {}
  } catch {
    devicesCache = {}
  }
  return devicesCache
}

async function saveDevices(map) {
  devicesCache = map
  await mkdir(LOG_DIR, { recursive: true })
  await writeFile(DEVICE_FILE, JSON.stringify(map, null, 2), { mode: 0o600 })
}

function newDeviceToken() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'
  return Array.from({ length: 43 }, () => chars[Math.floor(Math.random() * chars.length)]).join('')
}

/** 从请求里取设备凭证：优先 header，其次 cookie。 */
function deviceTokenFrom(req, urlObject) {
  const header = String(req.headers['x-dsh-pocket-device'] ?? '').trim()
  if (header) return header
  const cookie = String(req.headers.cookie ?? '')
  const match = cookie.match(/(?:^|;\s*)dsh-pocket-device=([^;]+)/)
  if (match) return decodeURIComponent(match[1])
  return String(urlObject?.searchParams?.get('device') ?? '').trim()
}
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
/** 三种连接方式。默认 Tailscale。 */
// 顺序即门槛从低到高：Cloudflare（手机零安装）→ Tailscale（需账号）→ EasyTier（需海外 App + 付费）
const MODES = ['lan', 'cloudflare', 'tailscale', 'easytier']
const MODE_LABELS = {
  cloudflare: 'Cloudflare',
  lan: '局域网',
  tailscale: 'Tailscale',
  easytier: 'EasyTier',
}

/** 当前选中的模式（进程内）。持久化见 readMode/saveMode。 */
let currentMode = 'lan'
/** Cloudflare quick 隧道（懒创建；同一时刻只跑一个）。 */
let cloudflareTunnel = null
/** dsh web 的监听端口，apply() 里赋值；modeStatus 用它起隧道。 */
let dshWebPortRef = null

/**
 * EasyTier 的网络名/密钥：首次生成后持久化，保证电脑和手机用同一套。
 * 换掉它们等于换了网络，手机那边的配置就失效了。
 */
async function readOrCreateEasyTierNetwork() {
  const file = join(LOG_DIR, 'easytier-network.json')
  try {
    const raw = await readFile(file, 'utf8')
    const parsed = JSON.parse(raw)
    if (parsed?.networkName && parsed?.networkSecret) return parsed
  } catch { /* 没存过 */ }
  const created = randomNetwork()
  try {
    await mkdir(LOG_DIR, { recursive: true })
    await writeFile(file, JSON.stringify(created), 'utf8')
  } catch { /* 存不了不影响本次 */ }
  return created
}

function modeFile() {
  return join(LOG_DIR, 'mode.json')
}

async function readMode() {
  try {
    const raw = await readFile(modeFile(), 'utf8')
    const value = JSON.parse(raw)?.mode
    if (MODES.includes(value)) return value
  } catch { /* 没存过 */ }
  // 默认 Cloudflare：手机端零安装，是唯一"扫码即连、什么都不用装"的方式
  return 'lan'
}

async function saveMode(mode) {
  try {
    await mkdir(LOG_DIR, { recursive: true })
    await writeFile(modeFile(), JSON.stringify({ mode }), 'utf8')
  } catch { /* 存不了不影响本次使用 */ }
}

/** Cloudflare 隧道实例（端口取自 dsh web 的监听端口）。 */
function cloudflareFor(port) {
  if (!cloudflareTunnel || cloudflareTunnel.port !== port) {
    cloudflareTunnel = new CloudflareTunnel({ port, log: (line) => void logLine(line) })
  }
  return cloudflareTunnel
}

/**
 * 当前连接方式的统一状态视图（面板和 pair.create 共用）。
 *
 * 三种方式对外的形状一致：address / qr / state / error，面板只需要渲染一套 UI。
 * - tailscale: 固定域名（需先装 Tailscale 并登录）
 * - cloudflare: quick 隧道（每次启动地址都会变，所以实时生成）
 * - easytier: 暂未实现，返回 not-supported，面板据此显示「即将支持」
 *
 * @returns {Promise<{mode: string, label: string, address: string|null, qr: string|null,
 *   state: string, error: string|null, modes: {id: string, label: string}[]}>}
 */
async function modeStatus() {
  currentMode = await readMode()
  const modes = MODES.map((id) => ({ id, label: MODE_LABELS[id] }))
  // 访问密码与连接方式无关，所有分支都要带上。
  // 之前只在 tailscaleStatus 里返回，切到 modeStatus 后漏了 → 面板显示「—」（用户反馈）。
  const pin = await readPin()
  const base = {
    mode: currentMode,
    label: MODE_LABELS[currentMode],
    modes,
    pin,
    pinSet: Boolean(pin),
  }

  if (currentMode === 'cloudflare') {
    // 隧道必须指向**插件代理**（PROXY_PORT），不能指向 dsh web 本体。
    // 指向本体时 Host 是隧道域名、不经过 forwardHeaders 的 loopback 改写，
    // 而 DSH 的 /api 只信任 loopback / trustedHosts：
    //   GET  /            → 200（首页不做 Host 校验）
    //   POST /api/...     → 403 forbidden（peer 不是 owner）
    // App 又把 403 映射成 invalidPin，于是用户看到「配对没成功」——
    // 明明 token 和服务端都正常（2026-11-15 在阿里云上抓到的就是这个）。
    const port = PROXY_PORT
    if (!port) {
      return { ...base, address: null, qr: null, state: 'error', error: '拿不到 dsh web 端口' }
    }
    const tunnel = cloudflareFor(port)
    const snap = tunnel.status()

    // 已就绪 → 直接给地址
    if (snap.state === 'ready' && snap.url) {
      const qr = await QRCode.toDataURL(snap.url, { margin: 1, width: 360 })
      return { ...base, address: snap.url, qr, state: 'ready', error: null, phase: null }
    }

    // 启动中 → 不阻塞这次 RPC，前端轮询就能看到进度。
    // **不能在 status 里 await tunnel.start()**：首次要下载 24MB + 等隧道注册，
    // 会把 RPC 拖到超时，前端只看到 "invalid server-response failure"（2026-11-15 实测）。
    if (snap.state !== 'starting') {
      void tunnel.start().catch((error) => {
        void logLine(`cloudflare start failed: ${error?.message ?? error}`)
      })
    }
    const downloading = snap.phase === 'locating' || snap.phase === 'downloading'
      || snap.phase === 'extracting' || snap.phase === 'retrying'
    return {
      ...base,
      address: null,
      qr: null,
      state: 'starting',
      error: null,
      phase: snap.phase ?? null,
      detail: downloading
        ? `首次使用，正在准备 cloudflared（约 24MB）：${snap.phaseDetail ?? ''}`
        : '正在启动 Cloudflare 隧道…',
    }
  }

  if (currentMode === 'lan') {
    // 局域网直连：不经过任何隧道。同一 Wi-Fi 下这是最快最稳的方式。
    const ip = selectLanIPv4()
    const port = dshWebPortRef
    // 诊断：lan 分支返回 error 时最常见的两个原因就是这两个为 null
    void logLine(`lan status: ip=${ip ?? 'null'} dshPort=${port ?? 'null'} proxyPort=${PROXY_PORT}`)
    if (!ip || !port) {
      return {
        ...base,
        address: null,
        qr: null,
        state: 'error',
        error: ip
          ? '拿不到 dsh web 端口'
          : '没有找到局域网地址：请确认电脑已连上 Wi-Fi 或有线网络',
      }
    }
    // 必须用代理端口：DSH 自己只监听 127.0.0.1:${port}，手机连不上。
    // 代理（PROXY_PORT）已经在 0.0.0.0 上监听并转发到 DSH。
    const address = lanEntryUrl(ip, PROXY_PORT)
    const qr = await QRCode.toDataURL(address, { margin: 1, width: 360 })
    return { ...base, address, qr, state: 'ready', error: null }
  }

  if (currentMode === 'easytier') {
    // EasyTier 是 P2P 组网，不是"给我一个公网 URL"。
    // 电脑跑 easytier-core 建虚拟网卡（需要 root，插件代不了），
    // 手机端在 iOS 上根本跑不了 EasyTier —— 官方给的路子是 WireGuard 门户：
    // 电脑导出 wg 配置，手机用 WireGuard App 导入。
    const { cli } = await findEasytier()
    if (!cli) {
      return {
        ...base,
        address: null,
        qr: null,
        state: 'error',
        error: '没找到 easytier-cli。先安装 EasyTier（brew install easytier 或它的官方脚本），再回来刷新。',
      }
    }

    const wg = await readWireGuardPortal(cli)
    if (!wg) {
      // 还没建好门户：给出该执行的命令 + 随机网络名/密钥
      const net = await readOrCreateEasyTierNetwork()
      // 用 launchd 装成系统服务：开机自启 + 崩溃自动重启 + 后台常驻。
      // 比原来 `sudo easytier-core ...` 手动跑稳得多——那种方式关终端就断、重启电脑就没了。
      const { core: corePath } = await findEasytier()
      const cmd = installServiceCommand({
        corePath: corePath ?? '~/.local/bin/easytier-core',
        networkName: net.networkName,
        networkSecret: net.networkSecret,
        ipv4: '10.14.14.1',
        socksPort: EASYTIER_SOCKS_PORT,
      })
      return {
        ...base,
        address: null,
        qr: null,
        state: 'needs-setup',
        error: '还没启动 EasyTier 服务。复制下面的命令到终端执行（一次即可，装成开机自启的后台服务），然后点刷新。',
        command: cmd,
        hint: '装成服务后会开机自启、崩溃自动重启。手机端在 Shadowrocket 里加载下方订阅（全局路由要选「配置」而不是「代理」）。',
      }
    }

    // 有配置：把 Endpoint 换成本机可达地址（easytier 常给 0.0.0.0）
    const lanIp = selectLanIPv4()
    const host = lanIp || ''
    const config = normalizeWireGuardConfig(wg, host, EASYTIER_PORTAL_PORT)
    const qr = await QRCode.toDataURL(config, { margin: 1, width: 360 })

    // **手机要连的是虚拟网络里的 DSH 入口，不是局域网 IP**。
    // WireGuard 只负责让手机进 10.14.14.0/24；DSH 本身在 127.0.0.1，
    // 靠代理的 0.0.0.0:3091 在虚拟网络上暴露出来。
    // 所以 App 里该填 http://10.14.14.1:3091。
    const virtualHost = clientAddressFrom(wg).replace(/\.\d+$/, '.1')
    return {
      ...base,
      address: `http://${virtualHost}:${PROXY_PORT}`,
      qr,
      state: 'ready',
      error: null,
      config,
      // Shadowrocket 这类代理客户端用这个订阅 URL（配置里带了显式规则）
      confUrl: lanIp ? `http://${lanIp}:${PROXY_PORT}${CHANNEL}/easytier.conf` : null,
      // 配对码（面板上方大二维码）本来就是 http://10.14.14.1:3091/?pair=xxx，
      // 手机代理配好后扫它即可自动登录。这里要把顺序讲清楚，否则用户会以为只能手填密码。
      hint: `先在手机代理里加载下方订阅（一次性），之后扫上方二维码即自动连接 http://${virtualHost}:${PROXY_PORT}，无需密码。`,
    }
  }

  // tailscale（默认）
  const ts = await tailscaleStatus()
  return {
    ...base,
    address: ts.httpsUrl ?? null,
    qr: ts.qr ?? null,
    state: ts.httpsUrl ? 'ready' : 'error',
    error: ts.httpsUrl ? null : 'Tailscale 未就绪：请确认已安装并登录 Tailscale',
  }
}

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

/** APNs device token 存储。和设备凭证放同一目录，都不入库。 */
const PUSH_TOKENS_FILE = join(LOG_DIR, 'push-tokens.json')

async function readPushTokens() {
  try {
    const raw = await readFile(PUSH_TOKENS_FILE, 'utf8')
    const parsed = JSON.parse(raw)
    return parsed && typeof parsed === 'object' ? parsed : {}
  } catch {
    return {}
  }
}

async function savePushTokens(tokens) {
  await mkdir(LOG_DIR, { recursive: true })
  await writeFile(PUSH_TOKENS_FILE, JSON.stringify(tokens, null, 2))
}

/**
 * 当前可见会话状态（App 上报，30 秒过期）。
 *
 * 为什么带过期：App 被杀或锁屏后不会再有上报，
 * 若不失效会永久压制推送（用户会以为「通知坏了」）。
 */
let visibleSessionState = { sessionId: null, appActive: false, at: 0 }
/** 最近一次 App 上报的连接快照（telemetry 驱动）。 */
let latestConnectionSnapshot = null
/** 已写过标签的 rpcId（内存去重，只留最近 200 个，不读全文件）。 */
const taggedRpcIds = new Set()
function rememberTagged(rpcId) {
  taggedRpcIds.add(rpcId)
  if (taggedRpcIds.size > 200) {
    const oldest = taggedRpcIds.values().next().value
    taggedRpcIds.delete(oldest)
  }
}
const VISIBLE_STATE_TTL_MS = 30_000

function noteVisibleSession(payload) {
  visibleSessionState = {
    sessionId: typeof payload?.visibleSessionId === 'string' ? payload.visibleSessionId : null,
    appActive: payload?.appActive === true,
    at: Date.now(),
  }
}

function freshVisibleSession(now = Date.now()) {
  if (!visibleSessionState.sessionId) return null
  if (now - visibleSessionState.at > VISIBLE_STATE_TTL_MS) return null
  return visibleSessionState
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
  dshWebPortRef = dshPort ?? null
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
    // 保留**外部真实 Host**再改写 Host 给 DSH 用。
    //
    // 为什么必须留：refresh 要用 Host 生成 302 的跳转地址。代理把 Host 改成
    // 127.0.0.1 之后，插件拼出的是 http://127.0.0.1:.../?token=...，手机跟随过去
    // 等于访问它自己的 localhost —— 结果是「服务端 refresh ok，App 说没拿到 cookie」。
    if (typeof headers.host === 'string') copy['x-dsh-original-host'] = headers.host
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
        // 与 upgrade 同一个坑：上游读到一半断开时 proxyRes 会抛 ECONNRESET，
        // 不接管就会打死整个 host。
        proxyRes.on('error', () => { try { res.destroy() } catch { /* 已关闭 */ } })
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
      // **必须给两个裸 socket 都挂 'error'**。
      // 手机切后台 / 换网 / 切连接方式时，对端会发 RST，此时 socket 的读操作抛
      // ECONNRESET；没有 error 监听就会冒泡成 uncaughtException，
      // 而 DSH 的 installFailLoud 对任何未捕获异常都是 process.exit(1)
      // —— 表现为「手机一动，桌面 DSH 整个退出」（2026-11-15 定位，当天崩了 5 次）。
      socket.on('error', () => { try { proxySocket.destroy() } catch { /* 已关闭 */ } })
      proxySocket.on('error', () => { try { socket.destroy() } catch { /* 已关闭 */ } })

      const lines = [`HTTP/1.1 101 Switching Protocols`]
      for (const [key, value] of Object.entries(proxyRes.headers)) {
        if (value !== undefined) lines.push(`${key}: ${Array.isArray(value) ? value.join(', ') : value}`)
      }
      try {
        socket.write(lines.join('\r\n') + '\r\n\r\n')
        if (proxyHead?.length) socket.write(proxyHead)
        if (head?.length) proxySocket.write(head)
      } catch { /* 写失败说明对端已断，交给 error 监听处理 */ }
      proxySocket.pipe(socket)
      socket.pipe(proxySocket)
    })
    // 上游没有升级时（401 未认证 / 403 / 404）走这条。
    //
    // `upgrade` 事件只在服务器返回 101 时触发。DSH 因为 cookie 缺失或过期返回 401 时，
    // `response` 事件会触发，但没人接的话这个请求就永远挂着 —— 客户端看到「连上了但 0 字节」，
    // 表现是 App 的 Live 一直 reconnecting、帧率 0.00/s，而普通 HTTP 请求完全正常。
    proxyReq.on('response', (proxyRes) => {
      proxyRes.on('error', () => { try { socket.destroy() } catch { /* 已关闭 */ } })
      const headers = [`HTTP/1.1 ${proxyRes.statusCode} ${proxyRes.statusMessage ?? ''}`]
      for (const [key, value] of Object.entries(proxyRes.headers)) {
        if (value !== undefined) headers.push(`${key}: ${Array.isArray(value) ? value.join(', ') : value}`)
      }
      try { socket.write(headers.join('\r\n') + '\r\n\r\n') } catch { /* 已断开 */ }
      proxyRes.pipe(socket)
    })
    proxyReq.on('error', () => socket.destroy())
    proxyReq.end()
  })
  server.on('error', (error) => ctx?.logger?.warn?.(`dsh-pocket-ios: 稳定入口端口 ${PROXY_PORT} 不可用（${error?.message ?? error}）`))
  // 兜底：任何未经 upgrade 路径处理的客户端连接错误，都不能让它冒泡到 host。
  server.on('clientError', (error, socket) => {
    try { socket.destroy() } catch { /* 已关闭 */ }
    void error
  })
  // 绑 0.0.0.0 而不是只绑回环：局域网模式下手机要能直连这个端口。
  // 安全性由 DSH 自身的登录态保证（非 /dsh-pocket-ios/ 前缀的请求会原样转发给 DSH，
  // 未认证时 DSH 返回 401）——这和 dsh-pocket 的做法一致。
  server.listen(PROXY_PORT, '0.0.0.0', () => {
    ctx?.logger?.info?.(`dsh-pocket-ios: 稳定入口 http://0.0.0.0:${PROXY_PORT} → DSH 127.0.0.1:${dshPort}`)
  })
  return () => {
    try { server.close() } catch { /* 已关闭 */ }
    // DSH 退出/重载时必须显式停掉 cloudflared，否则它变成孤儿进程一直挂着：
    // 反复重启会累积多个隧道（每轮换一个域名），既浪费又让人以为「地址老在变」。
    try { void cloudflareFor(PROXY_PORT).stop() } catch { /* 忽略 */ }
  }
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
        // 免浏览器会话的白名单：这三个端点自带凭证校验
        //   login  = PIN
        //   pair   = 一次性配对 token
        //   refresh= 长期设备凭证（DSH 重启后 cookie 失效时用它换新票）
        const isLogin = rawPath === `${CHANNEL}/login`
          || rawPath === `${CHANNEL}/pair`
          || rawPath === `${CHANNEL}/refresh`
          // easytier.conf 免认证：代理客户端下载它时没有 DSH cookie。
          // 内容只有局域网 IP + SOCKS5 端口 + 网段，不含任何凭证。
          || rawPath === `${CHANNEL}/easytier.conf`
          // telemetry 免 cookie：App 的 URLSession 在 refresh 之后没稳定带上新的
          // dsh-auth（实测每 10 秒 403），而它只写「状态计数」到本机日志，
          // 不含消息正文或凭证，放开认证的代价可控。
          || rawPath === `${CHANNEL}/telemetry`
          // cli.* 免 cookie，但**只允许本机回环**（CLI 在服务器终端里跑，
          // 没法走浏览器登录那套）。IP 校验在每个端点内部做。
          || rawPath === `${CHANNEL}/cli.pair`
          || rawPath === `${CHANNEL}/cli.status`
          || rawPath === `${CHANNEL}/cli.mode`
        if (!isLogin && typeof connection?.requestRejection === 'function') {
          const rejection = connection.requestRejection(req)
          if (rejection !== undefined) {
            // 只对遥测打日志：它本该每 10 秒来一次，被 401 拦掉时日志里必须有痕迹，
            // 否则「App 没发」和「发了被拒」两种情况长得一模一样，没法排查。
            if (rawPath.endsWith('/telemetry')) {
              const hasCookie = typeof req.headers.cookie === 'string' && req.headers.cookie.length > 0
              await logLine(`telemetry rejected (${rejection}) host=${String(req.headers.host ?? '')} cookie=${hasCookie ? 'yes' : 'none'}`)
            }
            send(res, rejection, { ok: false })
            return
          }
        }
        const urlObject = new URL(req.url ?? '/', 'http://127.0.0.1')

        // CLI 专用：查当前连接方式状态（只允许本机）。
        // 让服务器场景不必开浏览器就能确认「现在连的是哪条路、有没有就绪」。
        if (urlObject.pathname === `${CHANNEL}/cli.status`) {
          const remote = String(req.socket?.remoteAddress ?? '')
          if (!/^(127\.|::1$|::ffff:127\.)/.test(remote)) {
            send(res, 403, { ok: false, error: 'cli.status 只允许本机访问' })
            return
          }
          const status = await modeStatus()
          send(res, 200, {
            type: 'server-response',
            result: {
              ok: true,
              value: {
                mode: status.mode,
                state: status.state,
                address: status.address,
                error: status.error,
                pinSet: status.pinSet,
                modes: MODES,
              },
            },
          })
          return
        }

          // App 遥测：App 每 10 秒上报一次连接状态，写 JSONL 供事后排查。
          //
          // 为什么需要：手机侧的 liveState / rate / sinceFrameMs / outbox 只存在 App 里，
          // Mac 侧只能看到「消息到没到」。两边时间对齐后才能分清
          // 「是网络慢」还是「App 状态机卡住」——之前只能靠用户截图猜。
          if (urlObject.pathname === `${CHANNEL}/telemetry`) {
            if (req.method !== 'POST') { send(res, 405, { ok: false }); return }
            let payload
            try {
              payload = await readBody(req)
            } catch {
              send(res, 400, { ok: false }); return
            }
            // 顺手记录「App 现在在看哪个会话」：推送巡检要用它抑制打扰。
            noteVisibleSession(payload)
            // 以及「App 现在的连接快照」：给每条消息打来源标签用。
            latestConnectionSnapshot = snapshotFromTelemetry(payload)
            await logLine(`telemetry received (${Object.keys(payload ?? {}).length} keys)`)
            try {
              const telemetryDir = join(homedir(), 'Library', 'Logs', 'DSHPocket')
              await mkdir(telemetryDir, { recursive: true })
              const day = new Date().toISOString().slice(0, 10).replace(/-/g, '')
              const line = JSON.stringify({ receivedAt: new Date().toISOString(), ...payload })
              await appendFile(join(telemetryDir, `app-telemetry-${day}.jsonl`), line + '\n', 'utf8')
            } catch { /* 落盘失败不影响 App 上报 */ }
            send(res, 200, { ok: true })
            return
          }

        // CLI 专用：切换连接方式（只允许本机）。
        // 复用 mode.set 的互斥逻辑：切走 cloudflare 前先停隧道，避免两个隧道并存。
        if (urlObject.pathname === `${CHANNEL}/cli.mode`) {
          const remote = String(req.socket?.remoteAddress ?? '')
          if (!/^(127\.|::1$|::ffff:127\.)/.test(remote)) {
            send(res, 403, { ok: false, error: 'cli.mode 只允许本机访问' })
            return
          }
          let requested = urlObject.searchParams.get('mode') ?? ''
          if (!requested) {
            try {
              const raw = await readRawBody(req)
              requested = String(JSON.parse(raw || '{}')?.mode ?? '')
            } catch { /* 用 query 里的 */ }
          }
          if (!MODES.includes(requested)) {
            send(res, 400, { ok: false, error: `未知模式 ${requested}，可选：${MODES.join(' / ')}` })
            return
          }
          if (currentMode === 'cloudflare' && requested !== 'cloudflare' && cloudflareTunnel) {
            await cloudflareTunnel.stop()
          }
          currentMode = requested
          await saveMode(requested)
          const status = await modeStatus()
          send(res, 200, {
            type: 'server-response',
            result: { ok: true, value: { mode: status.mode, state: status.state, address: status.address } },
          })
          return
        }

        // CLI 专用配对端点：给「DSH 装在无 GUI 服务器上、只在终端里出码」的场景用。
        // 不走 cookie/auth（CLI 拿不到浏览器会话），改为严格限制来源必须是本机回环，
        // 且只返回一次性的配对 token，不暴露任何长期凭证。
        if (urlObject.pathname === `${CHANNEL}/cli.pair`) {
          const remote = String(req.socket?.remoteAddress ?? '')
          const isLocal = /^(127\.|::1$|::ffff:127\.)/.test(remote)
          if (!isLocal) {
            send(res, 403, { ok: false, error: 'cli.pair 只允许本机访问' })
            return
          }
          const status = await modeStatus()
          if (!status.address) {
            send(res, 409, { ok: false, error: '当前连接方式还没有地址，先在 DSH 面板里让它就绪' })
            return
          }
          const pairToken = generatePairToken()
          pairTokens.set(pairToken, { expiresAt: Date.now() + PAIR_TTL_MS })
          const pairURL = `${status.address}/?pair=${encodeURIComponent(pairToken)}`
          await logLine(`cli pair token created: ${pairURL.replace(/pair=([^&]{6})[^&]*/, 'pair=$1…')}`)
          send(res, 200, {
            type: 'server-response',
            result: { ok: true, value: { url: pairURL, expiresIn: PAIR_TTL_MS / 1000, mode: status.mode } },
          })
          return
        }

        // Shadowrocket 订阅配置：代理类客户端靠它把 10.14.14.0/24 显式指向 SOCKS5。
        // 不经过 RPC，直接吐纯文本。
        if (urlObject.pathname === `${CHANNEL}/easytier.conf`) {
          const lanIp = selectLanIPv4()
          if (!lanIp) {
            send(res, 503, { ok: false, error: '没有局域网地址' })
            return
          }
          const conf = shadowrocketConf({
            socksHost: lanIp,
            socksPort: EASYTIER_SOCKS_PORT,
            portalCidr: EASYTIER_CLIENT_CIDR,
          })
          res.writeHead(200, {
            'content-type': 'text/plain; charset=utf-8',
            'cache-control': 'no-store',
          })
          res.end(conf)
          return
        }

        const endpoint = endpointFromPath(urlObject.pathname)
        if (endpoint === undefined) {
          send(res, 404, { ok: false })
          return
        }
/**
 * 推断原始请求该用 http 还是 https。
 *
 * 关键：**局域网 / 私有网段一律 http**。它们没有 TLS 证书，拼成 https 会直接连不上。
 *
 * 旧实现只把 loopback 当 http，其他全当 https，于是局域网配对成功后 302 到
 * `https://192.168.x.x:3091/` —— 手机连不上，表现为「局域网模式进不去」。
 * Tailscale 那条本来就是 https，所以从日志看不出来（2026-11-15 定位）。
 *
 * @param {import('node:http').IncomingMessage} req
 * @param {string} host 请求的 Host 头
 * @returns {'http'|'https'}
 */
function guessProto(req, host) {
  const forwarded = String(req.headers['x-forwarded-proto'] ?? '').split(',')[0].trim()
  if (forwarded === 'http' || forwarded === 'https') return forwarded
  const bare = String(host).replace(/:\d+$/, '')
  if (/^(127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|169\.254\.)/.test(bare)) return 'http'
  if (/^(localhost|\[::1\]|.*\.local)$/i.test(bare)) return 'http'
  return 'https'
}

        // 登录端点：不需要已有浏览器会话，用本插件自己的 PIN 换 DSH 的认证 cookie。
        // APNs token 注册。App 拿到 token 后调这里，服务端据此推送。
        if (endpoint === 'push.register' || endpoint === 'push.unregister') {
          if (req.method !== 'POST') { send(res, 405, { ok: false }); return }
          let body = {}
          try { body = JSON.parse(await readRawBody(req)) } catch { body = {} }
          const token = String(body?.token ?? '').trim()
          if (!/^[0-9a-fA-F]{32,200}$/.test(token)) { send(res, 400, { ok: false, error: 'bad token' }); return }
          const tokens = await readPushTokens()
          if (endpoint === 'push.unregister') {
            delete tokens[token]
            await savePushTokens(tokens)
            await logLine('push unregistered')
            send(res, 200, { ok: true })
            return
          }
          const environment = String(body?.environment ?? 'production') === 'sandbox' ? 'sandbox' : 'production'
          tokens[token] = {
            environment,
            addedAt: tokens[token]?.addedAt ?? Date.now(),
            lastSeenAt: Date.now(),
          }
          await savePushTokens(tokens)
          await logLine(`push registered (${environment}, ${Object.keys(tokens).length} device)`)
          send(res, 200, { ok: true })
          return
        }

        // App 上报「我正在看哪个会话」：推送前用它抑制打扰。
        if (endpoint === 'push.visible') {
          if (req.method !== 'POST') { send(res, 405, { ok: false }); return }
          let body = {}
          try { body = JSON.parse(await readRawBody(req)) } catch { body = {} }
          noteVisibleSession(body)
          send(res, 200, { ok: true })
          return
        }

        if (endpoint === 'pair') {
          if (req.method !== 'POST' && req.method !== 'GET') { send(res, 405, { ok: false }); return }
          let token = urlObject.searchParams.get('token') ?? urlObject.searchParams.get('pair') ?? ''
          if (req.method === 'POST') {
            const raw = await readRawBody(req)
            const contentType = String(req.headers['content-type'] ?? '')
            if (contentType.includes('application/json')) {
              try { token = JSON.parse(raw)?.token ?? JSON.parse(raw)?.pair ?? token } catch { /* ignore */ }
            } else {
              token = new URLSearchParams(raw).get('token') ?? new URLSearchParams(raw).get('pair') ?? token
            }
          }
          const record = pairTokens.get(String(token))
          if (!record || record.expiresAt < Date.now()) {
            pairTokens.delete(String(token))
            await logLine('pair rejected (expired/unknown)')
            send(res, 401, { ok: false })
            return
          }
          // 不在这里删 token：同一张码可能被点开两次（浏览器预取、用户刷新、
          // 或在两台设备上先后打开）。过期由 expiresAt 控制，不必靠「用掉即删」。
          // 删掉的后果是「第二次打开就说过期」，用户完全无法理解。
          const host = String(req.headers.host ?? '')
          if (!host || typeof connection?.authenticatedUrl !== 'function') { send(res, 503, { ok: false }); return }
          const proto = guessProto(req, host)
          const target = connection.authenticatedUrl(`${proto}://${host}/`)
          // 顺带签发长期设备凭证：cookie 是 session 级的，DSH 重启后失效，
          // App 靠这份凭证换新 cookie，不必重新扫码。
          let deviceCookie = []
          try {
            const devices = await readDevices()
            // 复用同名设备，避免每次配对都堆一条。
            const deviceName = String(req.headers['user-agent'] ?? 'iOS').slice(0, 80)
            let existing = Object.keys(devices).find((key) => devices[key]?.name === deviceName)
            if (!existing) {
              existing = newDeviceToken()
              devices[existing] = { name: deviceName, createdAt: Date.now(), lastUsedAt: Date.now() }
              await saveDevices(devices)
            } else {
              devices[existing].lastUsedAt = Date.now()
              await saveDevices(devices)
            }
            deviceCookie = [`dsh-pocket-device=${encodeURIComponent(existing)}; Path=/; Max-Age=31536000; HttpOnly; SameSite=Lax`]
          } catch (error) {
            await logLine(`device token issue failed: ${error?.message ?? error}`)
          }
          await logLine('pair login ok')
          const headers = { location: target, 'cache-control': 'no-store' }
          if (deviceCookie.length) headers['set-cookie'] = deviceCookie
          res.writeHead(302, headers)
          res.end()
          return
        }
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
          const proto = guessProto(req, host)
          const target = connection.authenticatedUrl(`${proto}://${host}/`)
          res.writeHead(302, { location: target, 'cache-control': 'no-store' })
          res.end()
          return
        }
        if (req.method !== 'POST') {
          send(res, 404, { ok: false })
          return
        }
        // body 解析容错：refresh 这类端点不需要 JSON body，
        // 之前直接 readBody 会在进入分支前抛「Unexpected end of JSON input」，
        // App 只看到 HTTP 200 + ok:false，却因为没有新 cookie 而误判「换票成功」。
        let body = {}
        try {
          body = await readBody(req)
        } catch {
          body = {}
        }
        const rpcId = typeof body?.rpcId === 'string' ? body.rpcId : ''
        // 用长期设备凭证换新的 dsh-auth cookie。
        // DSH 重启后原 cookie 失效，App 调这里拿新的，不必重新扫码。
        if (endpoint === 'refresh') {
          if (req.method !== 'POST' && req.method !== 'GET') { send(res, 405, { ok: false }); return }
          const deviceToken = deviceTokenFrom(req, urlObject)
          const devices = await readDevices()
          const record = deviceToken ? devices[deviceToken] : undefined
          if (!record) {
            await logLine('refresh rejected (unknown device)')
            send(res, 401, { ok: false })
            return
          }
          const host = String(req.headers.host ?? '')
          if (!host || typeof connection?.authenticatedUrl !== 'function') { send(res, 503, { ok: false }); return }
          const proto = guessProto(req, host)
          const target = connection.authenticatedUrl(`${proto}://${host}/`)
          record.lastUsedAt = Date.now()
          await saveDevices(devices)
          await logLine('refresh ok')
          res.writeHead(302, { location: target, 'cache-control': 'no-store' })
          res.end()
          return
        }
        // 撤销设备（用户在电脑端「已连接设备」里点删除）。
        if (endpoint === 'device.revoke') {
          const args = body?.payload?.args ?? body?.payload ?? body?.args ?? body ?? {}
          const target = String(args.device ?? args.token ?? '')
          const devices = await readDevices()
          if (target && devices[target]) {
            delete devices[target]
            await saveDevices(devices)
            await logLine('device revoked')
          }
          send(res, 200, { type: 'server-response', rpcId, result: { ok: true, value: { ok: true } } })
          return
        }
        // 列出已配对设备（供设置页展示与撤销）。
        if (endpoint === 'device.list') {
          const devices = await readDevices()
          const value = Object.entries(devices).map(([token, info]) => ({
            token: `${token.slice(0, 6)}…`,
            full: token,
            name: info?.name ?? '',
            createdAt: info?.createdAt ?? 0,
            lastUsedAt: info?.lastUsedAt ?? 0
          }))
          send(res, 200, { type: 'server-response', rpcId, result: { ok: true, value: { devices: value } } })
          return
        }
        // 切换连接方式：停掉旧隧道、启动新隧道，返回新状态。
        if (endpoint === 'mode.set') {
          const args = body?.payload?.args ?? body?.payload ?? body?.args ?? body ?? {}
          const next = String(args.mode ?? '')
          if (!MODES.includes(next)) {
            send(res, 200, { type: 'server-response', rpcId, result: { ok: false, error: { code: 'bad-request', message: `unknown mode ${next}` } } })
            return
          }
          // 互斥：切走之前先把上一种停掉，避免两个隧道进程同时跑
          if (currentMode === 'cloudflare' && next !== 'cloudflare' && cloudflareTunnel) {
            await cloudflareTunnel.stop()
          }
          currentMode = next
          await saveMode(next)
          await logLine(`mode -> ${next}`)
          // 立刻回一个轻量状态：切到 cloudflare 时隧道要下载/注册，不能阻塞在这里
          const value = { mode: next, label: MODE_LABELS[next], modes: MODES.map((id) => ({ id, label: MODE_LABELS[id] })), address: null, qr: null, state: 'starting', error: null, phase: null }
          send(res, 200, { type: 'server-response', rpcId, result: { ok: true, value } })
          return
        }
        if (endpoint === 'mode.status') {
          const value = await modeStatus()
          send(res, 200, { type: 'server-response', rpcId, result: { ok: true, value } })
          return
        }
        if (endpoint === 'pair.create') {
          const pairToken = generatePairToken()
          // 60 秒太短：从「看到二维码」到「手机上点开链接」要经过拿手机、开相机、
          // 扫、等隧道冷启动，实测很容易超时（用户反馈「显示配对已过期」）。
          // 放宽到 5 分钟，仍是一次连接的时间尺度，不会长期留后门。
          pairTokens.set(pairToken, { expiresAt: Date.now() + PAIR_TTL_MS })
          // 按当前连接方式取地址：Cloudflare 用 quick 隧道，Tailscale 用固定地址，
          // 都没有时回退到请求 Host（局域网直连）。
          const status = await modeStatus()
          let base = status.address
          if (!base) {
            // 回退到**局域网可达**的地址，绝不能用 req.headers.host。
            // 面板是用户在浏览器里用 http://127.0.0.1:<port> 打开的，那个 host 拼出来的
            // 二维码在手机上指向手机自己 → 扫了必失败（2026-11-15 实测：三种模式全废）。
            // 局域网没地址时最后才用 host 兜底（至少本机测试能用）。
            const lanIp = selectLanIPv4()
            if (lanIp) {
              base = `http://${lanIp}:${PROXY_PORT}`
            } else {
              // 优先用代理带过来的外部 Host；直连（无代理）时才退回 req.headers.host。
            const host = String(req.headers['x-dsh-original-host'] ?? req.headers.host ?? '')
              const forwardedProto = String(req.headers['x-forwarded-proto'] ?? '').split(',')[0].trim()
              const isLoopback = /^(127\.0\.0\.1|localhost|\[::1\])(:\d+)?$/i.test(host)
              base = `${forwardedProto || (isLoopback ? 'http' : 'https')}://${host}`
            }
          }
          // **必须走插件自己的 /pair 端点**，不是根路径。
          // 之前生成的是 `${base}/?pair=`，代理会把它当普通请求转发给 DSH，
          // DSH 不认识 ?pair 参数 → 返回 401 → App 显示「无法到达电脑」。
          // 配对逻辑（校验 token、换 cookie）在 `${CHANNEL}/pair` 里（2026-11-15 定位）。
          // **App 的契约：根路径 + `?pair=`**，路径由 App 自己拼。
          // 见 ConnectionModel+Connect.swift：
          //   1. 从 URL 取 `?pair=` 的值
          //   2. POST 到 `url.appending(path: "dsh-pocket-ios/pair")`，body 用 `token=`
          //   3. 检查是否拿到 `dsh-auth*` cookie
          //
          // 所以这里必须给 `${base}/?pair=`：
          //   - 写成 `${base}${CHANNEL}/pair?...` → App 会 append 成双路径
          //   - 参数写成 `?token=` → App 会走 DSH launchToken 分支（那个每次重启都变，
          //     必然「sign in link 过期」）
          const pairURL = `${base}/?pair=${encodeURIComponent(pairToken)}`
          const qr = await QRCode.toDataURL(pairURL, { margin: 1, width: 360 })
          // 把生成的 URL 记下来（token 只留前 6 位），排查「扫出来的地址不对」时一眼可见
          await logLine(`pair token created: ${pairURL.replace(/pair=([^&]{6})[^&]*/, 'pair=$1…')}`)
          send(res, 200, { type: 'server-response', rpcId, result: { ok: true, value: { url: pairURL, qr, expiresIn: PAIR_TTL_MS / 1000 } } })
          return
        }
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
        // 面板只认这一个端点：返回统一形状（含 mode/modes/address/qr/state）。
        // 兼容旧字段：httpsUrl/pin 仍在 tailscaleStatus 里，需要的话单独取。
        const value = await modeStatus()
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

  // 插件移动端聚合。**用独立的 inject 作用域**：`pluginManager` 不可用时
  // 只是这个能力不挂载，PIN/配对/代理照常工作。
  // 教训来自 2026-11-16：给 dsh-plugin-panel 加工具时把注册写在主流程里，
  // 一抛错整个插件就不加载，所有路由变 405。
  try {
    if (typeof ctx?.inject === 'function') {
      ctx.inject(['pluginManager'], (scoped) => {
        const dispose = registerPluginAggregator(scoped)
        if (typeof scoped?.effect === 'function') {
          scoped.effect(() => dispose, 'dsh-pocket-ios: 插件移动端聚合')
        }
        scoped?.logger?.info?.('dsh-pocket-ios: 插件移动端聚合已挂载 /dsh-pocket/plugins/list')
      })
    } else if (ctx?.pluginManager) {
      registerPluginAggregator(ctx)
    } else {
      ctx?.logger?.warn?.('dsh-pocket-ios: 没有 pluginManager，插件聚合未挂载')
    }
  } catch (error) {
    ctx?.logger?.warn?.(`dsh-pocket-ios: 挂载插件聚合失败：${String(error?.message ?? error)}`)
  }

  startPushWatcher()

  return attachStableProxy(ctx, route.handler)
}

/**
 * 推送巡检：每 10 秒扫一次活跃会话，发现「新的 turn/end 且用户没继续」就推 APNs。
 *
 * 为什么不用事件订阅：插件只注入了 connection / webServer，拿不到会话状态；
 * 而会话日志就在磁盘上，读尾部比接事件更直接（同一个数据源，dsh-net-record 已验证）。
 *
 * 失败一律静默：推送是锦上添花，不能因为它拖垮插件。
 */
function startPushWatcher() {
  const APNS_DIR = join(LOG_DIR, 'apns')
  const SESSIONS_DIR = join(homedir(), '.dsh', 'sessions')
  const stateFile = join(LOG_DIR, 'push-state.json')
  const SCAN_INTERVAL_MS = 10_000

  /** sessionId -> { lastTurnEndSeq, lastNotifiedAt } */
  let state = {}
  let tokenCache = null
  let running = false

  async function loadState() {
    try {
      state = JSON.parse(await readFile(stateFile, 'utf8')) || {}
    } catch {
      state = {}
    }
  }

  async function persistState() {
    try {
      await mkdir(LOG_DIR, { recursive: true })
      await writeFile(stateFile, JSON.stringify(state))
    } catch { /* 状态丢了最多多推一次 */ }
  }

  /** 找 .p8 并建 token 缓存。凭证缺一个就返回 null（不推）。 */
  async function ensureTokenCache() {
    if (tokenCache) return tokenCache
    try {
      const entries = await readdir(APNS_DIR)
      const p8 = entries.find((name) => name.endsWith('.p8'))
      if (!p8) return null
      const keyId = p8.replace(/^AuthKey_/, '').replace(/\.p8$/, '')
      const teamId = process.env.DSH_APNS_TEAM_ID ?? 'T626DDUR47'
      const pem = await readFile(join(APNS_DIR, p8), 'utf8')
      tokenCache = new ProviderTokenCache({ keyId, teamId, privateKeyPem: pem })
      await logLine(`push: credentials loaded (key ${keyId})`)
      return tokenCache
    } catch {
      return null
    }
  }

  /**
   * 给这次尾部窗口里新出现的用户消息写连接标签。
   *
   * 为什么只用内存快照、过期就标 unknown：App 锁屏后 telemetry 会停，
   * 拿十年前的连接状态去标新消息比「不知道」更糟——会把人引到错误的方向。
   */
  async function recordConnectionTags(sessionId, events) {
    const tags = []
    for (const event of events) {
      const descriptor = messageDescriptor(event)
      if (!descriptor) continue
      if (taggedRpcIds.has(descriptor.rpcId)) continue
      const tag = buildTag({ sessionId, descriptor, snapshot: latestConnectionSnapshot })
      if (tag) tags.push(tag)
    }
    if (tags.length === 0) return
    try {
      await mkdir(LOG_DIR, { recursive: true })
      const lines = tags.map((tag) => JSON.stringify(tag)).join('\n') + '\n'
      await appendFile(join(LOG_DIR, 'connection-tags.jsonl'), lines, 'utf8')
      for (const tag of tags) rememberTagged(tag.rpcId)
      await logLine(`connection tags: +${tags.length}`)
    } catch (error) {
      await logLine(`connection tags failed: ${error?.message ?? error}`)
    }
  }

  async function pushOnce() {
    // 先扫一遍会话：**连接标签与推送解耦**。
    // 之前把标签记录写在 token 检查之后，结果「没有 push token 就永远不记标签」
    // —— 标签和推送是两个独立功能，不该互相阻塞。
    const sessions = listActiveSessionFiles(SESSIONS_DIR, { sinceMs: 30 * 60 * 1000 })
    const snapshots = []
    for (const session of sessions) {
      const events = readTailEvents(session.file)
      if (events.length === 0) continue
      await recordConnectionTags(session.sessionId, events)
      snapshots.push({ session, events })
    }

    const tokens = await readPushTokens()
    const tokenList = Object.entries(tokens)
    if (tokenList.length === 0) return
    const cache = await ensureTokenCache()
    if (!cache) return

    const visible = freshVisibleSession()
    for (const { session, events } of snapshots) {
      const sessionId = session.sessionId
      const entry = state[sessionId] ?? {}
      const lastSeq = events.filter((e) => e.type === 'turn/end').at(-1)?.seq ?? null
      if (lastSeq === null || entry.lastTurnEndSeq === lastSeq) continue

      const verdict = shouldNotify({
        sessionId,
        events,
        visibleSessionId: visible?.sessionId ?? null,
        appActive: visible?.appActive ?? false,
        visibleAt: visible?.at ?? null,
        lastNotifiedAt: entry.lastNotifiedAt ?? null,
      })
      if (!verdict.notify) {
        // 用户已经继续对话：记下 seq，避免下次重复判断
        if (verdict.reason === 'user-already-replied') {
          state[sessionId] = { ...entry, lastTurnEndSeq: lastSeq }
        }
        continue
      }

      const snippet = lastAssistantSnippet(events, 40)
      const body = snippet ? `「${snippet}」` : 'AI 回复完成'
      const payload = {
        aps: {
          alert: { title: '等你回复', body },
          sound: 'default',
        },
        sessionId,
      }
      const jwt = cache.get()
      let pushed = false
      for (const [token, meta] of tokenList) {
        const result = await sendPush({
          token,
          payload,
          jwt,
          environment: meta?.environment ?? 'production',
          topic: 'com.ruska.dsh-pocket-ios',
        })
        if (result.ok) {
          pushed = true
        } else if (result.reason === 'Unregistered' || result.reason === 'BadDeviceToken') {
          delete tokens[token]
          await savePushTokens(tokens)
          await logLine(`push: dropped stale token (${result.reason})`)
        } else {
          await logLine(`push failed: ${result.status ?? ''} ${result.reason ?? ''}`)
        }
      }
      if (pushed) {
        state[sessionId] = { lastTurnEndSeq: lastSeq, lastNotifiedAt: Date.now() }
        await persistState()
        await logLine(`push sent: ${sessionId.slice(0, 12)}`)
      }
    }
  }

  async function loop() {
    if (running) return
    running = true
    await loadState()
    while (true) {
      try {
        await pushOnce()
      } catch (error) {
        await logLine(`push watcher error: ${error?.message ?? error}`)
      }
      await new Promise((resolve) => setTimeout(resolve, SCAN_INTERVAL_MS))
    }
  }

  loop().catch(() => { /* 巡检永不阻塞插件 */ })
}
