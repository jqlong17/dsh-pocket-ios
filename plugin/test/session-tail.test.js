import test from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, writeFileSync, rmSync, mkdirSync, utimesSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import zlib from 'node:zlib'
import { readTailEvents, decodeFrames, findLatestSessionFile, listActiveSessionFiles } from '../lib/session-tail.js'

/** 造一个「一个事件一个 frame」的会话文件（和真实格式一致）。 */
function makeSessionFile(dir, events) {
  const chunks = events.map((event) =>
    zlib.zstdCompressSync(Buffer.from(JSON.stringify(event), 'utf8')))
  const buffer = Buffer.concat(chunks)
  const file = join(dir, 'session.v4.jsonl.zstd')
  writeFileSync(file, buffer)
  return file
}

let workDir
test.beforeEach(() => { workDir = mkdtempSync(join(tmpdir(), 'dsh-tail-')) })
test.afterEach(() => { rmSync(workDir, { recursive: true, force: true }) })

test('多帧文件能全部解出来（单帧解压只拿 1 条，这是本模块存在的原因）', () => {
  const events = [
    { type: 'turn/end', seq: 1 },
    { type: 'user/message', seq: 2 },
    { type: 'assistant/message', seq: 3 },
  ]
  const file = makeSessionFile(workDir, events)
  const decoded = readTailEvents(file)
  assert.equal(decoded.length, 3)
  assert.deepEqual(decoded.map((e) => e.seq), [1, 2, 3])
})

test('对照：直接解压整个 buffer 只能拿到第一个事件', () => {
  // 这条断言把「为什么必须切帧」钉死，防止有人图省事改回单次解压。
  const events = [{ type: 'turn/end', seq: 1 }, { type: 'turn/end', seq: 2 }]
  const chunks = events.map((e) => zlib.zstdCompressSync(Buffer.from(JSON.stringify(e))))
  const oneShot = zlib.zstdDecompressSync(Buffer.concat(chunks)).toString('utf8')
  assert.equal(oneShot.split('\n').filter(Boolean).length, 1)
})

test('只保留最后 maxFrames 个帧', () => {
  const events = Array.from({ length: 10 }, (_, i) => ({ type: 'turn/end', seq: i }))
  const file = makeSessionFile(workDir, events)
  const decoded = readTailEvents(file, { maxFrames: 3 })
  assert.deepEqual(decoded.map((e) => e.seq), [7, 8, 9])
})

test('半截帧（文件正在写）被跳过而不是抛错', () => {
  const good = zlib.zstdCompressSync(Buffer.from(JSON.stringify({ type: 'turn/end', seq: 1 })))
  const broken = Buffer.from([0x28, 0xb5, 0x2f, 0xfd, 0x00, 0x01, 0x02])  // 假 magic + 垃圾
  const file = join(workDir, 'session.v4.jsonl.zstd')
  writeFileSync(file, Buffer.concat([good, broken]))
  const decoded = readTailEvents(file)
  assert.equal(decoded.length, 1)
  assert.equal(decoded[0].seq, 1)
})

test('空文件和不存在文件都返回空数组', () => {
  const empty = join(workDir, 'session.v4.jsonl.zstd')
  writeFileSync(empty, Buffer.alloc(0))
  assert.deepEqual(readTailEvents(empty), [])
  assert.deepEqual(readTailEvents(join(workDir, 'nope.zstd')), [])
})

test('decodeFrames 对没有 magic 的输入返回空', () => {
  assert.deepEqual(decodeFrames(Buffer.from('not zstd at all')), [])
})

test('findLatestSessionFile 选中最近写过的会话', () => {
  const root = join(workDir, 'sessions')
  const mk = (project, sessionId, events) => {
    const dir = join(root, project, sessionId)
    mkdirSync(dir, { recursive: true })
    const file = join(dir, 'session.v4.jsonl.zstd')
    writeFileSync(file, Buffer.concat(events.map((e) => zlib.zstdCompressSync(Buffer.from(JSON.stringify(e))))))
    return file
  }
  mk('--proj-a--', 'session-old', [{ type: 'turn/end' }])
  const newest = mk('--proj-b--', 'session-new', [{ type: 'turn/end' }])

  // 把 newest 的 mtime 提到最前
  const now = Date.now() / 1000
  utimesSync(newest, now + 10, now + 10)

  const found = findLatestSessionFile(root)
  assert.ok(found)
  assert.equal(found.sessionId, 'session-new')
})

test('findLatestSessionFile 对空目录返回 null', () => {
  const root = join(workDir, 'empty-sessions')
  mkdirSync(root, { recursive: true })
  assert.equal(findLatestSessionFile(root), null)
  assert.equal(findLatestSessionFile(join(workDir, 'does-not-exist')), null)
})

test('listActiveSessionFiles 只返回窗口内的会话', () => {
  const root = join(workDir, 'sessions')
  const mk = (project, sessionId) => {
    const dir = join(root, project, sessionId)
    mkdirSync(dir, { recursive: true })
    const file = join(dir, 'session.v4.jsonl.zstd')
    writeFileSync(file, zlib.zstdCompressSync(Buffer.from(JSON.stringify({ type: 'turn/end' }))))
    return file
  }
  mk('--a--', 'session-recent')
  const oldFile = mk('--b--', 'session-old')
  const longAgo = (Date.now() - 3_600_000) / 1000
  utimesSync(oldFile, longAgo, longAgo)

  const active = listActiveSessionFiles(root, { sinceMs: 60_000 })
  assert.equal(active.length, 1)
  assert.equal(active[0].sessionId, 'session-recent')
})
