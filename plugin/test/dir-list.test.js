// dir.list：给 App 用的只读目录浏览（2026-11-26）
import test from 'node:test'
import assert from 'node:assert/strict'
import { mkdtemp, mkdir, writeFile, symlink, rm, realpath } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { normalizeRequestedPath, isInsideAllowedRoots, listSubdirectories, allowedRoots } from '../lib/dir-list.js'

test('~ 展开成家目录，空值默认为家目录', () => {
  const home = '/Users/demo'
  assert.equal(normalizeRequestedPath('~', home), '/Users/demo')
  assert.equal(normalizeRequestedPath('~/projects', home), '/Users/demo/projects')
  assert.equal(normalizeRequestedPath('', home), '/Users/demo')
})

test('相对路径必须被拒绝（避免靠 cwd 猜路径）', () => {
  assert.throws(() => normalizeRequestedPath('projects/foo', '/Users/demo'), /绝对路径/)
})

test('越界路径（不在 $HOME 与 /Volumes 下）被拒绝', () => {
  const roots = allowedRoots('/Users/demo')
  assert.equal(isInsideAllowedRoots('/Users/demo/projects', roots), true)
  assert.equal(isInsideAllowedRoots('/Users/demo2/x', roots), false)   // 前缀相同但不是子目录
  assert.equal(isInsideAllowedRoots('/etc', roots), false)
})

test('只列子目录：文件与隐藏目录不出现', async () => {
  const base = await mkdtemp(join(tmpdir(), 'dsh-dirlist-'))
  try {
    await mkdir(join(base, 'alpha'))
    await mkdir(join(base, 'beta'))
    await mkdir(join(base, '.hidden'))
    await writeFile(join(base, 'file.txt'), 'x')
    // 用 base 当 home 以便通过白名单
    const out = await listSubdirectories(base, { home: base })
    assert.deepEqual(out.dirs.map((d) => d.name), ['alpha', 'beta'])
    assert.equal(out.path, await realpath(base))   // /tmp 会解析成 /private/tmp
  } finally {
    await rm(base, { recursive: true, force: true })
  }
})

test('符号链接指向文件时不算目录', async () => {
  const base = await mkdtemp(join(tmpdir(), 'dsh-dirlist-'))
  try {
    await mkdir(join(base, 'real'))
    await writeFile(join(base, 'target.txt'), 'x')
    await symlink(join(base, 'target.txt'), join(base, 'link-to-file'))
    const out = await listSubdirectories(base, { home: base })
    assert.deepEqual(out.dirs.map((d) => d.name), ['real'])
  } finally {
    await rm(base, { recursive: true, force: true })
  }
})

test('不存在的目录给出 not-found', async () => {
  const base = await mkdtemp(join(tmpdir(), 'dsh-dirlist-'))
  try {
    await assert.rejects(
      () => listSubdirectories(join(base, 'nope'), { home: base }),
      (error) => error.code === 'not-found'
    )
  } finally {
    await rm(base, { recursive: true, force: true })
  }
})
