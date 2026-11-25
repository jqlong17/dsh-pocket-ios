/**
 * 面板（client/client.js）的静态回归检查。
 *
 * 面板是 React 组件，仓库里没有渲染测试的基础设施；但这次出的事都属于
 * 「结构/顺序/分支写错」这一类，用源码断言就能钉住，比手测可靠：
 *
 *  1. ref 在使用之前声明（否则 var 提升为 undefined → 整个面板白屏）
 *  2. 固定地址不能再用 `status.address || status.httpsUrl`（会把 ts.net 显示在 Cloudflare 下面）
 *  3. 切连接方式要先清掉旧二维码（地址可能一模一样，用户以为没生效）
 *  4. 插件回 { retry: true } 时要自己重试（否则要等下一次 10 分钟轮询）
 */
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'

const src = readFileSync(
  join(dirname(fileURLToPath(import.meta.url)), '..', 'client', 'client.js'),
  'utf8',
)
const lines = src.split('\n')
/** 去掉行注释后的代码（注释里会提到反例写法，不能当成代码匹配）。 */
const code = lines.map((l) => l.replace(/\/\/.*$/, '')).join('\n')

/** 某标识符首次出现的行号（0 起，找不到返回 -1）。 */
function firstLine(needle) {
  return lines.findIndex((l) => l.includes(needle))
}

test('pairBaseRef 必须在第一次使用之前声明（白屏回归）', () => {
  const decl = firstLine('var pairBaseRef = React.useRef(null)')
  const use = firstLine('pairBaseRef.current')
  assert.notEqual(decl, -1, '找不到 pairBaseRef 声明')
  assert.notEqual(use, -1, '找不到 pairBaseRef 使用')
  assert.ok(decl < use, `声明在第 ${decl + 1} 行，却在第 ${use + 1} 行就被使用`)
})

test('固定地址不再用 status.httpsUrl 兜底（Cloudflare 下显示 ts.net 的回归）', () => {
  assert.ok(
    !/status\.address\s*\|\|\s*status\.httpsUrl/.test(code),
    '仍存在 status.address || status.httpsUrl 的写法',
  )
})

test('切连接方式时先清空旧二维码', () => {
  const switchHandler = lines.slice(110, 150).join('\n')
  assert.match(switchHandler, /setPair\(\{\s*loading:\s*true/, '切模式时没有清空旧二维码')
})

test('插件回 retry 时面板会自己重试', () => {
  assert.match(src, /data\.retry/, '没有处理 data.retry')
  assert.match(src, /setTimeout\(function \(\) \{ generatePair\(\); \}/, '没有安排重试')
})

test('二维码地址与状态地址取自同一来源（pairBaseRef 兜底）', () => {
  const block = lines.slice(firstLine('var addressForMode') - 1, firstLine('var addressForMode') + 8).join('\n')
  assert.match(block, /pairBaseRef\.current/, 'addressForMode 没有用二维码地址兜底')
})
