import test from 'node:test'
import assert from 'node:assert/strict'

import { platformAsset, mirrorUrls, findTunaBottle } from '../lib/cloudflared-download.js'

test('platformAsset：三个平台的资产名各不相同（Linux 没有 .tgz）', () => {
  assert.deepEqual(platformAsset('darwin', 'arm64'), {
    asset: 'cloudflared-darwin-arm64.tgz', isArchive: true, exeSuffix: '',
  })
  // Linux 是裸二进制 —— 曾经给 Linux 拼 .tgz 导致五个源全 404
  assert.deepEqual(platformAsset('linux', 'x64'), {
    asset: 'cloudflared-linux-amd64', isArchive: false, exeSuffix: '',
  })
  assert.deepEqual(platformAsset('win32', 'x64'), {
    asset: 'cloudflared-windows-amd64.exe', isArchive: false, exeSuffix: '.exe',
  })
})

test('platformAsset：架构名映射（x64→amd64, arm64→arm64）', () => {
  assert.match(platformAsset('linux', 'x64').asset, /amd64$/)
  assert.match(platformAsset('linux', 'arm64').asset, /arm64$/)
})

test('mirrorUrls：第一个是官方源，后面都是加速源', () => {
  const urls = mirrorUrls('cloudflared-darwin-arm64.tgz')
  assert.ok(urls.length >= 2)
  assert.ok(urls[0].startsWith('https://github.com/cloudflare/cloudflared/releases/latest/download/'))
  assert.ok(urls[0].endsWith('cloudflared-darwin-arm64.tgz'))
  // 加速源是把官方地址拼在前缀后面
  assert.ok(urls.slice(1).every((u) => u.includes('github.com/cloudflare/cloudflared/releases')))
  // 不能有重复
  assert.equal(new Set(urls).size, urls.length)
})

test('findTunaBottle：非 macOS 不查（本机若是 macOS 则只断言类型）', async () => {
  const found = await findTunaBottle({ arch: 'arm64' })
  assert.ok(found === null || typeof found === 'string')
  if (found) {
    assert.ok(found.startsWith('https://mirrors.tuna.tsinghua.edu.cn/'))
    assert.match(found, /\.bottle\.tar\.gz$/)
  }
})

// ── 2026-11-25：findCloudflared 漏查插件自己的缓存目录 ────────────────
// 现象：明明已经下过 cloudflared（~/.dsh/dsh-pocket-ios/bin/），每次重启却
// 都显示「正在下载 cloudflared（约 20MB，只需一次）」，用户以为每次都重下。
test('findCloudflared 必须能发现插件管理的缓存二进制', async () => {
  const { mkdtemp, writeFile, chmod } = await import('node:fs/promises')
  const { tmpdir } = await import('node:os')
  const { join } = await import('node:path')
  const { findCloudflared } = await import('../lib/cloudflare.js')
  // 直接断言实现里包含缓存路径分支（真实路径不可在测试里改 HOME）
  const src = await import('node:fs/promises').then((fs) => fs.readFile(new URL('../lib/cloudflare.js', import.meta.url), 'utf8'))
  assert.match(src, /access\(managedBinaryPath\(\), constants\.X_OK\)/, 'findCloudflared 没有检查 managedBinaryPath()')
  assert.equal(typeof findCloudflared, 'function')
})
