/**
 * 静态接线检查：index.js 里用到的本地模块导出，必须真的 import 进来。
 *
 * 为什么需要：2026-11-25 的故障——`resolvePairBase` 在 pair.create 里被调用，
 * 但忘了 import。语法检查通过、单测全绿，**只有真跑起来才 ReferenceError**，
 * 面板表现为 "connection: invalid server-response failure"。
 */
import assert from 'node:assert/strict'
import { readFileSync, readdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'

const libDir = join(dirname(fileURLToPath(import.meta.url)), '..', 'lib')
const indexSource = readFileSync(join(libDir, 'index.js'), 'utf8')

/** 收集某个模块导出的标识符。 */
function exportsOf(file) {
  const src = readFileSync(join(libDir, file), 'utf8')
  const names = new Set()
  for (const m of src.matchAll(/export\s+(?:async\s+)?(?:function|const|let|class)\s+([A-Za-z_$][\w$]*)/g)) {
    names.add(m[1])
  }
  return names
}

const modules = readdirSync(libDir)
  .filter((f) => f.endsWith('.js') && f !== 'index.js')

for (const file of modules) {
  test(`${file} 的导出如果在 index.js 里用到，就必须 import`, () => {
    const used = []
    for (const name of exportsOf(file)) {
      // 调用、属性访问、传参三种用法都算「用到」
      const pattern = new RegExp(`(^|[^\\w$.])${name}\\s*[(.,)\\]}]`, 'm')
      if (pattern.test(indexSource)) used.push(name)
    }
    if (used.length === 0) return
    for (const name of used) {
      const imported = new RegExp(`import\\s*\\{[^}]*\\b${name}\\b[^}]*\\}\\s*from\\s*'\\./${file}'`).test(indexSource)
      assert.ok(imported, `index.js 用了 ${name}（来自 ${file}）但没有从该模块 import`)
    }
  })
}
