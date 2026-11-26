// dir-list
//
// 给 App 用的「只读目录浏览」：手机上选 Mac 上已有的文件夹，
// 再由 workspace/create 把它加成工作区（2026-11-26）。
//
// 为什么需要：DSH 没有目录浏览 RPC（桌面端用的是 Electron 对话框），
// 而 iOS 端拿不到 Mac 的文件系统。这个端点只做一件事：列子目录。
//
// 安全边界：
// - 只列目录，不列文件、不读内容（文件名也不外泄）
// - realpath 之后必须落在 $HOME 或 /Volumes 之下，防止 ../ 或符号链接越界
// - 由设备令牌鉴权（与 refresh 同一套）

import { readdir, realpath, stat } from 'node:fs/promises'
import { homedir } from 'node:os'
import { join, resolve, sep } from 'node:path'

/** 允许浏览的根。只放行用户目录与挂载卷。 */
export function allowedRoots(home = homedir()) {
  return [resolve(home), '/Volumes']
}

/** 展开 `~` 并转成绝对路径；相对路径直接拒绝（调用方只能传绝对路径或 ~ 开头）。 */
export function normalizeRequestedPath(raw, home = homedir()) {
  const value = String(raw ?? '').trim()
  if (!value) return resolve(home)
  if (value === '~') return resolve(home)
  if (value.startsWith('~/')) return resolve(join(home, value.slice(2)))
  if (!value.startsWith('/')) throw Object.assign(new Error('需要绝对路径或 ~ 开头'), { code: 'relative-path' })
  return resolve(value)
}

/** 是否在允许的根之内（按路径段比较，避免 /Users/a 误判 /Users/ab）。 */
export function isInsideAllowedRoots(target, roots = allowedRoots()) {
  return roots.some((root) => target === root || target.startsWith(root + sep))
}

/**
 * 列出某个目录下的子目录。
 * @returns {Promise<{path:string, parent:string|null, dirs:{name:string,path:string}[]}>}
 */
export async function listSubdirectories(rawPath, { home = homedir(), limit = 300 } = {}) {
  const requested = normalizeRequestedPath(rawPath, home)
  let real
  try {
    real = await realpath(requested)
  } catch (error) {
    throw Object.assign(new Error(`目录不存在：${requested}`), { code: 'not-found', cause: error })
  }
  // /tmp → /private/tmp 这类符号链接会让「白名单前缀比较」误判，先真实化根。
  const homeReal = await realpath(resolve(home)).catch(() => resolve(home))
  const roots = [homeReal, await realpath('/Volumes').catch(() => '/Volumes')]
  if (!isInsideAllowedRoots(real, roots)) {
    throw Object.assign(new Error('只能浏览用户目录或 /Volumes'), { code: 'outside-allowed-root' })
  }
  const info = await stat(real)
  if (!info.isDirectory()) throw Object.assign(new Error('不是目录'), { code: 'not-a-directory' })

  const entries = await readdir(real, { withFileTypes: true })
  const dirs = []
  for (const entry of entries) {
    if (!entry.isDirectory() && !entry.isSymbolicLink()) continue
    if (entry.name.startsWith('.')) continue   // 隐藏目录不展示，减少噪音
    const full = join(real, entry.name)
    // 符号链接指向文件的不算目录：只保留真实目录
    try {
      const target = await stat(full)
      if (!target.isDirectory()) continue
    } catch { continue }
    dirs.push({ name: entry.name, path: full })
    if (dirs.length >= limit) break
  }
  dirs.sort((a, b) => a.name.localeCompare(b.name, 'zh-Hans-CN'))
  const parent = real === homeReal || real === '/' ? null : resolve(real, '..')
  return { path: real, parent: parent && isInsideAllowedRoots(parent, roots) ? parent : null, dirs }
}
