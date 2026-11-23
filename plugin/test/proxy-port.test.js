import test from 'node:test'
import assert from 'node:assert/strict'
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import {
  portCandidates,
  selectProxyPort,
  readPersistedPort,
  writePersistedPort,
  preferredPort,
} from '../lib/proxy-port.js'

test('portCandidates：从起点连续给出候选', () => {
  assert.deepEqual(portCandidates(3091, 3), [3091, 3092, 3093])
})

test('portCandidates：非法起点回落到 3091', () => {
  assert.deepEqual(portCandidates(0, 2), [3091, 3092])
  assert.deepEqual(portCandidates('abc', 2), [3091, 3092])
})

test('selectProxyPort：首选空闲就选它，且不算回落', async () => {
  const free = new Set([3091])
  const got = await selectProxyPort({
    candidates: [3091, 3092],
    isFree: async (p) => free.has(p),
  })
  assert.deepEqual(got, { port: 3091, fallback: false })
})

test('selectProxyPort：首选被占则用下一个，并标记回落', async () => {
  const free = new Set([3092])
  const got = await selectProxyPort({
    candidates: [3091, 3092, 3093],
    isFree: async (p) => free.has(p),
  })
  assert.deepEqual(got, { port: 3092, fallback: true })
})

test('selectProxyPort：全部被占则交给系统分配', async () => {
  const got = await selectProxyPort({
    candidates: [3091, 3092],
    isFree: async () => false,
    ephemeral: 0,
  })
  assert.deepEqual(got, { port: 0, fallback: true })
})

test('preferredPort：环境变量优先于持久化值', () => {
  assert.equal(preferredPort({ envPort: 4100, persistedPort: 3092 }), 4100)
})

test('preferredPort：没有环境变量时优先沿用上次端口（跨重启稳定）', () => {
  assert.equal(preferredPort({ envPort: undefined, persistedPort: 3092 }), 3092)
})

test('preferredPort：都没有则用默认端口', () => {
  assert.equal(preferredPort({ envPort: undefined, persistedPort: null }), 3091)
})

test('持久化：写入后可读回，非法内容视为没有', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'dsh-port-'))
  const file = join(dir, 'proxy-port')
  try {
    assert.equal(await readPersistedPort(file), null)
    assert.equal(await writePersistedPort(file, 3093), true)
    assert.equal(await readPersistedPort(file), 3093)
  } finally {
    await rm(dir, { recursive: true, force: true })
  }
})
