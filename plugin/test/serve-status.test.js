import assert from 'node:assert/strict'
import test from 'node:test'
import { needsRepoint, parseServeStatus } from '../lib/serve-status.js'

const SAMPLE = `https://ruskamacbook-pro-1.tail619842.ts.net (tailnet only)\n|-- / proxy http://127.0.0.1:3092\n`

test('解析出地址与目标端口', () => {
  const r = parseServeStatus(SAMPLE)
  assert.equal(r.url, 'https://ruskamacbook-pro-1.tail619842.ts.net')
  assert.equal(r.port, 3092)
})

test('空输出 → 没有地址', () => {
  const r = parseServeStatus('')
  assert.equal(r.url, null)
  assert.equal(needsRepoint(r, 3091), true)
})

test('有地址但解析不出端口 → 不动（保守）', () => {
  const r = parseServeStatus('https://host.ts.net (tailnet only)')
  assert.equal(r.url, 'https://host.ts.net')
  assert.equal(r.port, null)
  assert.equal(needsRepoint(r, 3092), false)
})

test('端口一致 → 不需要重新指向', () => {
  assert.equal(needsRepoint(parseServeStatus(SAMPLE), 3092), false)
})

test('端口不一致 → 必须重新指向（本次 bug 的核心）', () => {
  assert.equal(needsRepoint(parseServeStatus(SAMPLE), 3091), true)
})
