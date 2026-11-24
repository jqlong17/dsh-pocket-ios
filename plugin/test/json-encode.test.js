import assert from 'node:assert/strict'
import test from 'node:test'
import { gunzipSync } from 'node:zlib'
import { COMPRESS_THRESHOLD, encodeJson, wantsGzip } from '../lib/json-encode.js'

test('识别 Accept-Encoding', () => {
  assert.equal(wantsGzip('gzip, deflate'), true)
  assert.equal(wantsGzip('br'), false)
  assert.equal(wantsGzip(undefined), false)
})

test('客户端不支持时不压缩', () => {
  const r = encodeJson({ a: 1 }, 'identity')
  assert.equal(r.compressed, false)
  assert.equal(r.body, '{"a":1}')
  assert.equal(r.headers['content-encoding'], undefined)
})

test('小于阈值不压缩', () => {
  const r = encodeJson({ a: 1 }, 'gzip')
  assert.equal(r.compressed, false)
})

test('大响应按 gzip 压缩且可还原', () => {
  const payload = { text: '会话历史'.repeat(500) }
  const r = encodeJson(payload, 'gzip')
  assert.equal(r.compressed, true)
  assert.equal(r.headers['content-encoding'], 'gzip')
  assert.equal(r.headers.vary, 'accept-encoding')
  const back = JSON.parse(gunzipSync(r.body).toString('utf8'))
  assert.deepEqual(back, payload)
})

test('阈值按字节算（汉字 3 字节）', () => {
  // 400 个汉字 = 1200 字节，超过 1024
  const payload = { t: '字'.repeat(400) }
  const r = encodeJson(payload, 'gzip')
  assert.equal(r.compressed, true)
  assert.ok(Buffer.byteLength(JSON.stringify(payload)) > COMPRESS_THRESHOLD)
})

test('自定义阈值生效', () => {
  const r = encodeJson({ a: 'x'.repeat(10) }, 'gzip', { threshold: 5 })
  assert.equal(r.compressed, true)
})
