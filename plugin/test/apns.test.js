import test from 'node:test'
import assert from 'node:assert/strict'
import { generateKeyPairSync, createVerify } from 'node:crypto'
import {
  derToRawSignature,
  makeProviderToken,
  ProviderTokenCache,
  JWT_REFRESH_MS,
} from '../lib/apns.js'

/** 生成一把 ES256 测试密钥。 */
function testKey() {
  const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' })
  return privateKey.export({ type: 'pkcs8', format: 'pem' })
}

test('JWT 结构正确（三段、ES256、kid）', () => {
  const pem = testKey()
  const jwt = makeProviderToken({ keyId: 'ABC1234567', teamId: 'T6266DUR47', privateKeyPem: pem })
  const parts = jwt.split('.')
  assert.equal(parts.length, 3)
  const header = JSON.parse(Buffer.from(parts[0], 'base64url').toString())
  assert.equal(header.alg, 'ES256')
  assert.equal(header.kid, 'ABC1234567')
  const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString())
  assert.equal(payload.iss, 'T6266DUR47')
  assert.equal(typeof payload.iat, 'number')
})

test('签名是 64 字节 raw r||s，不是 DER', () => {
  // 这是最关键的回归：DER 直接进 JWT 会被 APNs 403 拒绝（本仓库踩过）。
  const pem = testKey()
  const jwt = makeProviderToken({ keyId: 'K', teamId: 'T', privateKeyPem: pem })
  const signature = Buffer.from(jwt.split('.')[2], 'base64url')
  assert.equal(signature.length, 64)
  assert.notEqual(signature[0], 0x30)   // 不是 DER 的 SEQUENCE 开头
})

test('签名能被公钥验证（证明确实有效）', () => {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' })
  const pem = privateKey.export({ type: 'pkcs8', format: 'pem' })
  const jwt = makeProviderToken({ keyId: 'K', teamId: 'T', privateKeyPem: pem })
  const [h, p] = jwt.split('.')
  const raw = Buffer.from(jwt.split('.')[2], 'base64url')

  // raw r||s 转回 DER 才能用 verify
  const r = raw.subarray(0, 32)
  const s = raw.subarray(32)
  const encodeInt = (b) => {
    let v = b
    while (v.length > 1 && v[0] === 0x00) v = v.subarray(1)
    if (v[0] & 0x80) v = Buffer.concat([Buffer.from([0x00]), v])
    return Buffer.concat([Buffer.from([0x02, v.length]), v])
  }
  const body = Buffer.concat([encodeInt(r), encodeInt(s)])
  const der = Buffer.concat([Buffer.from([0x30, body.length]), body])

  const verifier = createVerify('sha256')
  verifier.update(`${h}.${p}`)
  assert.equal(verifier.verify({ key: publicKey, dsaEncoding: 'der' }, der), true)
})

test('derToRawSignature 拒绝非法输入', () => {
  assert.throws(() => derToRawSignature(Buffer.from([0x31, 0x00])))
  assert.throws(() => derToRawSignature(Buffer.from('short')))
})

test('token 缓存命中时复用，过期后重签', () => {
  let clock = 1_700_000_000_000
  const cache = new ProviderTokenCache({
    keyId: 'K', teamId: 'T', privateKeyPem: testKey(), now: () => clock,
  })
  const first = cache.get()
  assert.equal(cache.get(), first)          // 缓存命中
  clock += JWT_REFRESH_MS + 1000
  const second = cache.get()
  assert.notEqual(second, first)            // 过期后重签
})

test('缺少凭证时立刻报错而不是发出坏请求', () => {
  assert.throws(() => makeProviderToken({ keyId: '', teamId: 'T', privateKeyPem: 'x' }))
  assert.throws(() => makeProviderToken({ keyId: 'K', teamId: '', privateKeyPem: 'x' }))
})
