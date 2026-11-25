import assert from 'node:assert/strict'
import test from 'node:test'
import { isReachableStatus, probe } from '../lib/reachability.js'

test('200/401/403 算可达（401/403 是插件鉴权）', () => {
  assert.equal(isReachableStatus(200), true)
  assert.equal(isReachableStatus(401), true)
  assert.equal(isReachableStatus(403), true)
})

test('5xx/网络错误不算可达', () => {
  assert.equal(isReachableStatus(502), false)
  assert.equal(isReachableStatus(null), false)
})

test('probe 用 HEAD 并识别 401', async () => {
  let seenMethod = null
  const r = await probe('https://x.test/', {
    fetchImpl: async (_url, init) => { seenMethod = init.method; return { status: 401 } },
  })
  assert.equal(seenMethod, 'HEAD')
  assert.equal(r.ok, true)
  assert.equal(r.status, 401)
})

test('probe 捕获异常 → 不可达', async () => {
  const r = await probe('https://x.test/', { fetchImpl: async () => { throw new Error('ENOTFOUND') } })
  assert.equal(r.ok, false)
  assert.match(String(r.error), /ENOTFOUND/)
})
