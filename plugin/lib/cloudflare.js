// Cloudflare quick 隧道
//
// 为什么自己做：原先公网/局域网二维码由第三方 `dsh-pocket` 插件提供，
// 导致两套面板、四个二维码，用户分不清该扫哪个（2026-11-15 用户反馈）。
// 这里把 Cloudflare 收进本插件，三种连接方式在同一个面板里单选切换。
//
// quick 模式的特点：
//   - 不需要账号、不需要域名，`cloudflared tunnel --url` 直接给一个 trycloudflare.com 地址
//   - **每次重启地址都会变**，所以二维码必须实时生成，不能缓存
//   - 适合「只是想让手机连上」的场景，也是局域网使用时最快的一条路

import { spawn } from 'node:child_process'
import { access, constants } from 'node:fs/promises'
import { delimiter, join } from 'node:path'
import { homedir } from 'node:os'
import { ensureCloudflared } from './cloudflared-download.js'

/** 常见安装位置，PATH 里找不到时兜底探测。 */
const FALLBACK_PATHS = [
  '/opt/homebrew/bin/cloudflared',
  '/usr/local/bin/cloudflared',
  '/usr/bin/cloudflared',
]

/** 拿到 URL 的最长等待。cloudflared 通常 3–8 秒出地址，30 秒足够覆盖慢网络。 */
const READY_TIMEOUT_MS = 30_000

/**
 * 探测 cloudflared 可执行文件。
 * @returns {Promise<string|null>} 绝对路径；找不到返回 null
 */
export async function findCloudflared() {
  // 1) 先按 PATH 找（用户自建安装最常见）
  for (const dir of String(process.env.PATH ?? '').split(delimiter)) {
    if (!dir) continue
    const candidate = join(dir, process.platform === 'win32' ? 'cloudflared.exe' : 'cloudflared')
    try {
      await access(candidate, constants.X_OK)
      return candidate
    } catch { /* 继续找 */ }
  }
  // 2) 插件自己管理的缓存（上次下过就在这里）。以前漏了这条，
  //    每次都判定「没装」→ 重新下载，面板一直显示正在下载（2026-11-25）。
  try {
    await access(managedBinaryPath(), constants.X_OK)
    return managedBinaryPath()
  } catch { /* 没缓存 */ }
  // 3) 再试常见路径（GUI 启动的进程 PATH 往往不含 Homebrew）
  for (const candidate of FALLBACK_PATHS) {
    try {
      await access(candidate, constants.X_OK)
      return candidate
    } catch { /* 继续找 */ }
  }
  return null
}

/**
 * 从 cloudflared 的输出里抓 quick 隧道地址。
 * @param {string} text stdout/stderr 片段
 * @returns {string|null}
 */
export function extractQuickTunnelUrl(text) {
  const match = String(text ?? '').match(/https:\/\/[a-z0-9-]+\.trycloudflare\.com/i)
  return match ? match[0].replace(/\/$/, '') : null
}

/**
 * 本插件自己管理的二进制位置。
 * 放在 ~/.dsh 下与其它插件状态同处，卸载插件时一起清掉。
 */
export function managedBinaryPath() {
  return join(homedir(), '.dsh', 'dsh-pocket-ios', 'bin',
    process.platform === 'win32' ? 'cloudflared.exe' : 'cloudflared')
}

/**
 * 拿到一个可用的 cloudflared 路径。
 *
 * 顺序：
 *   1. PATH / Homebrew 里已有的（用户自己装过，直接用，省 20MB）
 *   2. 我们管理的那份（之前下过）
 *   3. 都没有 → 自动下载（多源 + 分块）
 *
 * @param {{ onPhase?: (phase: string, detail?: string) => void, signal?: AbortSignal }} [options]
 * @returns {Promise<string>}
 */
export async function ensureCloudflaredBinary({ onPhase = () => {}, signal } = {}) {
  const existing = await findCloudflared()
  if (existing) return existing
  return ensureCloudflared(managedBinaryPath(), { onPhase, signal })
}

/**
 * 一个 quick 隧道的生命周期。同一时刻只应存在一个。
 */
export class CloudflareTunnel {
  /**
   * @param {{ port: number, log?: (line: string) => void }} options
   */
  constructor({ port, log = () => {} }) {
    this.port = port
    this.log = log
    this.child = null
    this.url = null
    this.state = 'idle'   // idle | starting | ready | error
    this.error = null
    this.buffer = ''
  }

  /**
   * 启动隧道并等地址就绪。
   * @returns {Promise<string>} 公网地址
   */
  async start() {
    // 幂等：已经跑着就直接复用，避免切换时启两个进程
    if (this.state === 'ready' && this.url) return this.url
    // 单飞：并发调 start() 会让两个调用都看到 child === null，
    // 各自 await stop()（空操作）后各起一个 cloudflared，this.child 被后者覆盖，
    // 前一个进程失去引用再也杀不掉——表现为「越调越多隧道、地址一直在变」
    // （2026-11-15 在阿里云服务器上实测到 3 个并发进程 + 4 个不同地址）。
    if (this.startingPromise) return this.startingPromise
    this.startingPromise = this.#doStart().finally(() => { this.startingPromise = null })
    return this.startingPromise
  }

  async #doStart() {
    await this.stop()

    // 首次使用会自动下载（约 20MB，多源 + 分块）；已装则直接复用
    // 只有**真的没缓存**才算「定位/下载」；缓存命中直接进入启动。
    // 否则面板每次重启都显示「正在下载 cloudflared」，其实二进制早就在本地
    // （2026-11-25 用户反馈「为什么每次重启都要重新下载」）。
    this.phase = (await findCloudflared()) ? 'starting' : 'locating'
    let bin
    try {
      bin = await ensureCloudflaredBinary({
        onPhase: (phase, detail) => {
          this.phase = phase
          this.phaseDetail = detail ?? null
        },
      })
    } catch (error) {
      this.state = 'error'
      this.error = error?.message ?? String(error)
      throw error
    }

    this.state = 'starting'
    this.error = null
    this.buffer = ''
    this.url = null

    const child = spawn(bin, [
      'tunnel',
      '--url', `http://127.0.0.1:${this.port}`,
      '--no-autoupdate',
    ], { stdio: ['ignore', 'pipe', 'pipe'] })
    this.child = child

    const url = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        reject(new Error(`cloudflared ${READY_TIMEOUT_MS / 1000} 秒内没有给出地址`))
      }, READY_TIMEOUT_MS)

      const onChunk = (chunk) => {
        const text = String(chunk)
        this.buffer = (this.buffer + text).slice(-8000)   // 只留尾部，避免无限增长
        const found = extractQuickTunnelUrl(this.buffer)
        if (found) {
          clearTimeout(timer)
          resolve(found)
        }
      }
      child.stdout?.on('data', onChunk)
      child.stderr?.on('data', onChunk)   // cloudflared 把地址打在 stderr

      child.once('error', (err) => {
        clearTimeout(timer)
        reject(err)
      })
      child.once('exit', (code) => {
        clearTimeout(timer)
        // 主动 stop() 时也会触发 exit——那不是失败，不能 reject。
        // 之前没区分，导致每次切模式都记一条 "cloudflared 退出，code=null" 的假失败。
        if (this.stopping) return
        reject(new Error(`cloudflared 退出，code=${code}`))
      })
    }).catch((err) => {
      this.state = 'error'
      this.error = err?.message ?? String(err)
      throw err
    })

    this.url = url
    this.state = 'ready'
    this.log(`cloudflared 就绪: ${url}`)
    return url
  }

  /** 停掉子进程。幂等。 */
  async stop() {
    this.stopping = true
    const child = this.child
    this.child = null
    this.url = null
    if (this.state !== 'error') this.state = 'idle'
    if (!child) return
    try {
      child.kill('SIGTERM')
      // 给它 2 秒优雅退出，超时强杀
      const killed = await Promise.race([
        new Promise((resolve) => child.once('exit', () => resolve(true))),
        new Promise((resolve) => setTimeout(() => resolve(false), 2000)),
      ])
      if (!killed) child.kill('SIGKILL')
    } catch { /* 已经死了 */ }
    this.stopping = false
  }

  /** 状态快照（不启动）。 */
  status() {
    // 进程已经退出、但状态还停在 ready 的情况真会发生：DSH 被 kill -9 重启时
    // 子进程成了孤儿（或被系统清理），插件内存里却还是「隧道已就绪」。
    // 不修正的话 modeStatus 会一直返回一个连不上的地址，用户扫码后一头雾水
    // （2026-11-15 服务器上实测：杀光 cloudflared 后 cli.pair 仍返回旧域名）。
    if (this.state === 'ready' && this.child && this.child.exitCode !== null) {
      this.state = 'idle'
      this.url = null
      this.child = null
    }
    return { state: this.state, url: this.url, error: this.error, phase: this.phase ?? null, phaseDetail: this.phaseDetail ?? null }
  }
}
