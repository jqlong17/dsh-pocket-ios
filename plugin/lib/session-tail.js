/**
 * 会话文件读取：只读尾部 + 按 zstd magic 切帧。
 *
 * 为什么不能直接 `zstdDecompressSync(整个文件)`：
 * 会话日志有几十 MB、约 3 万个独立 zstd 帧（一个事件一帧），
 * Node 的解压 API 只处理第一个帧，直接调用只能拿到 1 条事件（实测）。
 *
 * 为什么只读尾部：推送只关心「最近的 turn/end」，读全文件既慢又没必要。
 */
import fs from 'node:fs'
import zlib from 'node:zlib'

const ZSTD_MAGIC = Buffer.from([0x28, 0xb5, 0x2f, 0xfd])
/** 尾部读多少字节。1 MB 足够覆盖最近几百个事件。 */
export const TAIL_BYTES = 1024 * 1024
/** 只解压最后多少个帧（越新的越靠后）。 */
export const MAX_FRAMES = 200

/**
 * 读会话文件尾部的事件。
 * @param {string} file 会话 .zstd 文件
 * @returns {Array<object>} 事件（时间升序，可能不完整——只覆盖尾部窗口）
 */
export function readTailEvents(file, { tailBytes = TAIL_BYTES, maxFrames = MAX_FRAMES } = {}) {
  let fd
  try {
    fd = fs.openSync(file, 'r')
    const size = fs.fstatSync(fd).size
    if (size === 0) return []
    const start = Math.max(0, size - tailBytes)
    const buffer = Buffer.alloc(size - start)
    fs.readSync(fd, buffer, 0, buffer.length, start)
    return decodeFrames(buffer, maxFrames)
  } catch {
    return []
  } finally {
    if (fd !== undefined) {
      try { fs.closeSync(fd) } catch { /* 已关闭 */ }
    }
  }
}

/**
 * 把一段含多个 zstd 帧的字节切成帧并逐帧解压。
 * 导出是为了单测（不需要真实会话文件）。
 */
export function decodeFrames(buffer, maxFrames = MAX_FRAMES) {
  const positions = []
  let cursor = 0
  while (true) {
    const found = buffer.indexOf(ZSTD_MAGIC, cursor)
    if (found === -1) break
    positions.push(found)
    cursor = found + ZSTD_MAGIC.length
  }
  if (positions.length === 0) return []

  const startIndex = Math.max(0, positions.length - maxFrames)
  const events = []
  for (let i = startIndex; i < positions.length; i += 1) {
    const from = positions[i]
    const to = i + 1 < positions.length ? positions[i + 1] : buffer.length
    if (to - from < 8) continue
    let text
    try {
      text = zlib.zstdDecompressSync(buffer.subarray(from, to)).toString('utf8')
    } catch {
      continue   // 半截帧（文件正在写）直接跳过
    }
    for (const line of text.split('\n')) {
      const trimmed = line.trim()
      if (!trimmed) continue
      try { events.push(JSON.parse(trimmed)) } catch { /* 不是 JSON */ }
    }
  }
  return events
}

/** 会话目录里最近被写过的会话文件。 */
export function findLatestSessionFile(sessionsDir) {
  let best = null
  let entries
  try {
    entries = fs.readdirSync(sessionsDir, { withFileTypes: true })
  } catch {
    return null
  }
  for (const projectEntry of entries) {
    if (!projectEntry.isDirectory()) continue
    const projectDir = `${sessionsDir}/${projectEntry.name}`
    let sessionEntries
    try {
      sessionEntries = fs.readdirSync(projectDir, { withFileTypes: true })
    } catch {
      continue
    }
    for (const sessionEntry of sessionEntries) {
      if (!sessionEntry.isDirectory() || !sessionEntry.name.startsWith('session-')) continue
      const file = `${projectDir}/${sessionEntry.name}/session.v4.jsonl.zstd`
      try {
        const stat = fs.statSync(file)
        if (!best || stat.mtimeMs > best.mtimeMs) {
          best = { file, mtimeMs: stat.mtimeMs, sessionId: sessionEntry.name }
        }
      } catch { /* 没这个文件 */ }
    }
  }
  return best
}

/**
 * 所有「最近活跃」的会话文件（mtime 在窗口内），用于同时监控多个会话。
 */
export function listActiveSessionFiles(sessionsDir, { sinceMs = 30 * 60 * 1000, now = Date.now() } = {}) {
  const results = []
  let entries
  try {
    entries = fs.readdirSync(sessionsDir, { withFileTypes: true })
  } catch {
    return results
  }
  for (const projectEntry of entries) {
    if (!projectEntry.isDirectory()) continue
    const projectDir = `${sessionsDir}/${projectEntry.name}`
    let sessionEntries
    try {
      sessionEntries = fs.readdirSync(projectDir, { withFileTypes: true })
    } catch {
      continue
    }
    for (const sessionEntry of sessionEntries) {
      if (!sessionEntry.isDirectory() || !sessionEntry.name.startsWith('session-')) continue
      const file = `${projectDir}/${sessionEntry.name}/session.v4.jsonl.zstd`
      try {
        const stat = fs.statSync(file)
        if (now - stat.mtimeMs <= sinceMs) {
          results.push({ file, mtimeMs: stat.mtimeMs, sessionId: sessionEntry.name })
        }
      } catch { /* 没这个文件 */ }
    }
  }
  return results
}
