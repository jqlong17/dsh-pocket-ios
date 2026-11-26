import assert from 'node:assert/strict'
import test from 'node:test'
import { clientKey, createLoginLimiter, randomPin } from '../lib/pin-policy.js'

test('密码 12 位，同时含字母和数字，且不含易混字符', () => {
  for (let i = 0; i < 500; i++) {
    const pin = randomPin()
    assert.equal(pin.length, 12)
    assert.match(pin, /[A-Za-z]/)
    assert.match(pin, /[0-9]/)
    assert.doesNotMatch(pin, /[0O1lI]/)
    assert.match(pin, /^[A-Za-z0-9]{12}$/)
  }
})

test('密码不是固定开头（必须打乱）', () => {
  const heads = new Set(Array.from({ length: 50 }, () => randomPin()[0]))
  assert.ok(heads.size > 5, '首位字符种类太少，说明没有打乱')
})

test('连续失败 5 次触发锁定，锁定期内 check 返回 retryAfter', () => {
  const limiter = createLoginLimiter()
  const t0 = 1_000_000
  for (let i = 0; i < 4; i++) assert.equal(limiter.recordFailure('1.2.3.4', t0 + i), 0)
  assert.equal(limiter.check('1.2.3.4', t0 + 10), null)
  assert.equal(limiter.recordFailure('1.2.3.4', t0 + 10), 5 * 60 * 1000)
  const locked = limiter.check('1.2.3.4', t0 + 20)
  assert.ok(locked && locked.retryAfter > 0)
})

test('锁定到期后可以再试，再失败锁得更久', () => {
  const limiter = createLoginLimiter()
  const t0 = 1_000_000
  for (let i = 0; i < 5; i++) limiter.recordFailure('a', t0 + i)
  const afterFirstLock = t0 + 5 * 60 * 1000 + 10
  assert.equal(limiter.check('a', afterFirstLock), null)
  for (let i = 0; i < 5; i++) limiter.recordFailure('a', afterFirstLock + i)
  const second = limiter.check('a', afterFirstLock + 4)
  assert.ok(second && second.retryAfter >= 14 * 60, '第二次锁定应更长')
})

test('成功登录清零，不影响其他 IP', () => {
  const limiter = createLoginLimiter()
  const t0 = 1_000_000
  for (let i = 0; i < 5; i++) limiter.recordFailure('b', t0 + i)
  limiter.clear('b')
  assert.equal(limiter.check('b', t0 + 10), null)
  assert.equal(limiter.size, 0)
})

test('限流按真实客户端取键：转发头优先，最后才用 socket 地址', () => {
  assert.equal(clientKey({ 'x-forwarded-for': '1.1.1.1, 2.2.2.2' }, '127.0.0.1'), '1.1.1.1')
  assert.equal(clientKey({ 'cf-connecting-ip': '3.3.3.3' }, '127.0.0.1'), '3.3.3.3')
  assert.equal(clientKey({ 'tailscale-user-login': 'a@b.com' }, '127.0.0.1'), 'user:a@b.com')
  assert.equal(clientKey({}, '10.0.0.9'), '10.0.0.9')
})
