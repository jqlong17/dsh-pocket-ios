import test from 'node:test'
import assert from 'node:assert/strict'
import {
  snapshotFromTelemetry,
  classifyAddress,
  isSnapshotFresh,
  isIOSMessage,
  messageDescriptor,
  buildTag,
  SNAPSHOT_TTL_MS,
} from '../lib/connection-tags.js'

/** 造一份 App 遥测 payload。 */
function telemetry({ network = 'wifi', currentAddress = 'http://192.168.1.18:3091', rttMs = 12, ok = true } = {}) {
  return {
    probeNetwork: network,
    probes: [
      { address: 'https://a.ts.net', isCurrent: false, ok: false },
      { address: currentAddress, isCurrent: true, ok, rttMs },
    ],
  }
}

/** 造一条 iOS 用户消息事件。 */
function iosMessage({ rpcId = 'rpc-1', seq = 10, time = 1_000, text = '你好\u2063\u2063' } = {}) {
  return {
    type: 'user/message',
    seq,
    time,
    data: { source: { kind: 'user', rpcId }, content: [{ type: 'text', text }] },
  }
}

test('从遥测提取网络与路径', () => {
  const snapshot = snapshotFromTelemetry(telemetry({ network: 'cellular', currentAddress: 'https://x.ts.net', rttMs: 23 }), 1000)
  assert.equal(snapshot.network, 'cellular')
  assert.equal(snapshot.path, 'tailscale')
  assert.equal(snapshot.rttMs, 23)
  assert.equal(snapshot.reachable, true)
  assert.equal(snapshot.at, 1000)
})

test('没有 isCurrent 时标 unknown 而不是瞎猜', () => {
  const snapshot = snapshotFromTelemetry({ probeNetwork: 'wifi', probes: [] }, 1000)
  assert.equal(snapshot.path, 'unknown')
  assert.equal(snapshot.network, 'wifi')
  assert.equal(snapshot.rttMs, null)
})

test('过期快照不用于标新消息', () => {
  const snapshot = snapshotFromTelemetry(telemetry(), 1000)
  assert.equal(isSnapshotFresh(snapshot, 1000 + SNAPSHOT_TTL_MS), true)
  assert.equal(isSnapshotFresh(snapshot, 1000 + SNAPSHOT_TTL_MS + 1), false)
  assert.equal(isSnapshotFresh(null, 1000), false)
})

test('地址分类', () => {
  assert.equal(classifyAddress('https://a.tail1234.ts.net'), 'tailscale')
  assert.equal(classifyAddress('https://foo.trycloudflare.com'), 'cloudflare')
  assert.equal(classifyAddress('http://192.168.1.18:3091'), 'lan')
  assert.equal(classifyAddress('http://10.0.0.5:3091'), 'lan')
  assert.equal(classifyAddress('http://172.20.1.1:3091'), 'lan')
  assert.equal(classifyAddress('http://203.0.113.9:3091'), 'public')
  assert.equal(classifyAddress('http://localhost:3091'), 'lan')
  assert.equal(classifyAddress(''), 'unknown')
  assert.equal(classifyAddress(null), 'unknown')
})

test('识别 iOS 消息标记', () => {
  assert.equal(isIOSMessage('你好\u2063\u2063'), true)
  assert.equal(isIOSMessage('你好'), false)
  assert.equal(isIOSMessage(''), false)
  assert.equal(isIOSMessage(null), false)
})

test('只把真人消息当候选（注入类跳过）', () => {
  const injected = {
    type: 'user/message',
    seq: 1,
    data: { source: { kind: 'runtime-context' }, content: [{ type: 'text', text: 'x' }] },
  }
  assert.equal(messageDescriptor(injected), null)
  assert.equal(messageDescriptor({ type: 'assistant/message' }), null)
  assert.equal(messageDescriptor({ type: 'user/message', data: { source: { kind: 'user' } } }), null)  // 无 rpcId
})

test('从消息事件提取描述', () => {
  const d = messageDescriptor(iosMessage({ rpcId: 'abc', seq: 7, time: 500 }))
  assert.equal(d.rpcId, 'abc')
  assert.equal(d.seq, 7)
  assert.equal(d.messageAt, 500)
  assert.equal(d.ios, true)
})

test('组装标签：字段齐全且不含凭证', () => {
  const snapshot = snapshotFromTelemetry(telemetry({ network: 'cellular' }), 1000)
  const tag = buildTag({
    sessionId: 'session-x',
    descriptor: messageDescriptor(iosMessage({ rpcId: 'r1' })),
    snapshot,
    now: 2000,
  })
  assert.equal(tag.rpcId, 'r1')
  assert.equal(tag.sessionId, 'session-x')
  assert.equal(tag.ios, true)
  assert.equal(tag.network, 'cellular')
  assert.equal(tag.path, 'lan')
  assert.equal(tag.snapshotAgeMs, 1000)
  // 绝不含凭证类字段
  for (const forbidden of ['token', 'cookie', 'pin', 'deviceToken', 'authorization']) {
    assert.equal(forbidden in tag, false, `标签不该包含 ${forbidden}`)
  }
})

test('快照过期时标签标 unknown 而非留空', () => {
  const snapshot = snapshotFromTelemetry(telemetry(), 1000)
  const stale = buildTag({
    sessionId: 's',
    descriptor: messageDescriptor(iosMessage()),
    snapshot,
    now: 1000 + SNAPSHOT_TTL_MS + 5000,
  })
  assert.equal(stale.network, 'unknown')
  assert.equal(stale.path, 'unknown')
  assert.equal(stale.rttMs, null)
  assert.equal(stale.snapshotAgeMs, null)
})

test('没有描述时返回 null（不产生半截标签）', () => {
  assert.equal(buildTag({ sessionId: 's', descriptor: null, snapshot: null }), null)
})

test('Mac 端消息 ios 为 false', () => {
  const macMsg = iosMessage({ text: '从电脑发的' })
  const tag = buildTag({
    sessionId: 's',
    descriptor: messageDescriptor(macMsg),
    snapshot: snapshotFromTelemetry(telemetry(), 0),
    now: 0,
  })
  assert.equal(tag.ios, false)
})
