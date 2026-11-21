import test from 'node:test'
import assert from 'node:assert/strict'
import {
  shouldNotify,
  lastAssistantSnippet,
  DEFAULT_COOLDOWN_MS,
  VISIBLE_STATE_TTL_MS,
} from '../lib/push-scan.js'

/** 造一段事件序列的便捷函数。 */
function turnEnd(time = 1000) {
  return { type: 'turn/end', time }
}
function userMsg(time = 1000) {
  // 只有 source.kind === 'user' 才是真人消息
  return { type: 'user/message', time, data: { source: { kind: 'user' }, content: [] } }
}
function injectedMsg(time = 1000) {
  // 系统注入：同样是 user/message，但 kind 不是 user
  return { type: 'user/message', time, data: { source: { kind: 'runtime-context' } } }
}
function assistantMsg(time = 1000) {
  return { type: 'assistant/message', time, data: { content: [{ type: 'text', text: '好了' }] } }
}

test('新 turn/end 应该推送', () => {
  const r = shouldNotify({ sessionId: 'session-a', events: [userMsg(), assistantMsg(), turnEnd()], now: 10_000 })
  assert.equal(r.notify, true)
  assert.equal(r.reason, 'ok')
})

test('turn/end 之后用户又说话了就不推', () => {
  // 用户已经继续对话，说明他人在场，不需要提醒
  const r = shouldNotify({
    sessionId: 'session-a',
    events: [assistantMsg(), turnEnd(1000), userMsg(2000)],
    now: 10_000,
  })
  assert.equal(r.notify, false)
  assert.equal(r.reason, 'user-already-replied')
})

test('系统注入的 user/message 不该被当成用户已回复', () => {
  // 这是最容易误判的一类：runtime-context / skill-catalog 也是 user/message。
  // 误判会导致「永远不推」（本仓库在消息来源上踩过同样的坑）。
  const r = shouldNotify({
    sessionId: 'session-a',
    events: [assistantMsg(), turnEnd(1000), injectedMsg(2000)],
    now: 10_000,
  })
  assert.equal(r.notify, true)
})

test('前台正在看同一会话时不推', () => {
  const r = shouldNotify({
    sessionId: 'session-a',
    events: [assistantMsg(), turnEnd()],
    visibleSessionId: 'session-a',
    appActive: true,
    visibleAt: 9_000,
    now: 10_000,
  })
  assert.equal(r.notify, false)
  assert.equal(r.reason, 'user-viewing')
})

test('看 A 会话时 B 完成仍要推', () => {
  const r = shouldNotify({
    sessionId: 'session-a',          // 完成的是 A
    events: [assistantMsg(), turnEnd()],
    visibleSessionId: 'session-b',   // 用户看的是 B
    appActive: true,
    visibleAt: 9_000,
    now: 10_000,
  })
  assert.equal(r.notify, true)
})

test('可见状态过期后恢复推送', () => {
  // App 被杀 / 锁屏后可见状态必须失效，否则会一直压制推送。
  const r = shouldNotify({
    sessionId: 'session-a',
    events: [assistantMsg(), turnEnd()],
    visibleSessionId: 'session-a',
    appActive: true,
    visibleAt: 0,
    now: VISIBLE_STATE_TTL_MS + 5_000,
  })
  assert.equal(r.notify, true)
})

test('App 不在前台时可见状态无关', () => {
  const r = shouldNotify({
    sessionId: 'session-a',
    events: [assistantMsg(), turnEnd()],
    visibleSessionId: 'session-a',
    appActive: false,
    visibleAt: 9_999,
    now: 10_000,
  })
  assert.equal(r.notify, true)
})

test('冷却期内同一会话不重复推', () => {
  const r = shouldNotify({
    sessionId: 'session-a',
    events: [assistantMsg(), turnEnd()],
    lastNotifiedAt: 10_000,
    now: 10_000 + DEFAULT_COOLDOWN_MS - 1,
  })
  assert.equal(r.notify, false)
  assert.equal(r.reason, 'cooldown')
})

test('冷却期过后可以再推', () => {
  const r = shouldNotify({
    sessionId: 'session-a',
    events: [assistantMsg(), turnEnd()],
    lastNotifiedAt: 10_000,
    now: 10_000 + DEFAULT_COOLDOWN_MS,
  })
  assert.equal(r.notify, true)
})

test('没有 turn/end 不推', () => {
  const r = shouldNotify({ sessionId: 'session-a', events: [userMsg()], now: 10_000 })
  assert.equal(r.notify, false)
  assert.equal(r.reason, 'no-turn-end')
})

test('空事件不推', () => {
  assert.equal(shouldNotify({ sessionId: 'session-a', events: [], now: 10_000 }).notify, false)
  assert.equal(shouldNotify({ now: 10_000 }).notify, false)
})

test('助手文本片段用于推送正文', () => {
  const snippet = lastAssistantSnippet([
    { type: 'assistant/message', data: { content: [{ type: 'text', text: '  改好了，测试全绿  ' }] } },
  ])
  assert.equal(snippet, '改好了，测试全绿')
})

test('超长文本被截断', () => {
  const long = 'x'.repeat(100)
  const snippet = lastAssistantSnippet([
    { type: 'assistant/message', data: { content: [{ type: 'text', text: long }] } },
  ], 20)
  assert.equal(snippet.length, 21)   // 20 + 省略号
  assert.ok(snippet.endsWith('…'))
})

test('没有助手文本返回空串', () => {
  assert.equal(lastAssistantSnippet([userMsg()]), '')
  assert.equal(lastAssistantSnippet(null), '')
})
