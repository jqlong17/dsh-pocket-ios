import assert from 'node:assert/strict'
import test from 'node:test'
import { decideAfterProbe, resolvePairBase } from '../lib/pair-base.js'

test('有地址就直接用（任何模式）', () => {
  assert.equal(resolvePairBase({ mode: 'cloudflare', address: 'https://x.trycloudflare.com', lanIp: '10.0.0.2', port: 3091 }),
    'https://x.trycloudflare.com')
  assert.equal(resolvePairBase({ mode: 'tailscale', address: 'https://m.ts.net', lanIp: null, port: 3091 }),
    'https://m.ts.net')
})

test('Cloudflare 没地址时不出码，绝不回退局域网（用户投诉过）', () => {
  assert.equal(resolvePairBase({ mode: 'cloudflare', address: null, lanIp: '10.56.166.90', port: 3092 }), null)
})

test('局域网/EasyTier 没地址时回退局域网 IP', () => {
  assert.equal(resolvePairBase({ mode: 'lan', address: null, lanIp: '10.56.166.90', port: 3092 }),
    'http://10.56.166.90:3092')
})

test('没有局域网 IP 时也不出码', () => {
  assert.equal(resolvePairBase({ mode: 'lan', address: null, lanIp: null, port: 3092 }), null)
})

test('Cloudflare 地址可达 → 可以出码', () => {
  assert.equal(decideAfterProbe('cloudflare', { ok: true }), 'ready')
})

test('Cloudflare 地址不可达 → 等一会儿再出（避免首次扫码必失败）', () => {
  assert.equal(decideAfterProbe('cloudflare', { ok: false }), 'wait')
})

test('其它模式不做可达性判断', () => {
  assert.equal(decideAfterProbe('tailscale', { ok: false }), 'ok')
  assert.equal(decideAfterProbe('lan', { ok: false }), 'ok')
})
