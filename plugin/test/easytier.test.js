import test from 'node:test'
import assert from 'node:assert/strict'

import {
  extractWireGuardConfig,
  normalizeWireGuardConfig,
  clientAddressFrom,
  coreCommand,
  randomNetwork,
  findEasytier,
} from '../lib/easytier.js'

const SAMPLE = `2026-11-15 INF some log line
[Interface]
Address = 10.144.144.3/32
PrivateKey = abc123=
DNS = 10.144.144.1

[Peer]
PublicKey = xyz789=
AllowedIPs = 10.144.144.0/24, 192.168.1.0/24
Endpoint = 0.0.0.0:11011
PersistentKeepalive = 25`

test('extractWireGuardConfig：从带日志的输出里截出配置', () => {
  const out = extractWireGuardConfig(SAMPLE)
  assert.ok(out)
  assert.ok(out.startsWith('[Interface]'))
  assert.ok(out.includes('[Peer]'))
  // 前缀的日志行不能混进来
  assert.ok(!out.includes('INF some log line'))
})

test('extractWireGuardConfig：缺 [Peer] 视为无效', () => {
  assert.equal(extractWireGuardConfig('[Interface]\nAddress = 1.2.3.4/32'), null)
})

test('extractWireGuardConfig：完全没配置时返回 null', () => {
  assert.equal(extractWireGuardConfig('no config here'), null)
  assert.equal(extractWireGuardConfig(''), null)
})

// easytier-cli 的真实输出：带标记、带 # 注释、Address 是网络地址
const REAL = `portal_name: wireguard

############### client_config_start ###############

[Interface]
PrivateKey = 1y/dG8OzqbNIHkjCOffKW1KdieFkfl1i4GkAU3seKcU=
Address = 10.14.14.0/32 # should assign an ip from this cidr manually

[Peer]
PublicKey = 2lQgea43LmtZC8eCN3P5Xds2Vv0ngSl0Yfk9uDVwc3Q=
AllowedIPs = 10.14.14.0/24
Endpoint = 0.0.0.0:11500 # should be the public ip(or domain) of the vpn server
PersistentKeepalive = 25

############### client_config_end ###############
`

test('extractWireGuardConfig：按 client_config_start/end 标记截取', () => {
  const out = extractWireGuardConfig(REAL)
  assert.ok(out)
  assert.ok(out.startsWith('[Interface]'))
  assert.ok(!out.includes('client_config_end'))
  assert.ok(!out.includes('portal_name'))
})

test('normalizeWireGuardConfig：去掉 # 注释（WireGuard 不支持注释）', () => {
  const out = normalizeWireGuardConfig(extractWireGuardConfig(REAL), '192.168.1.10', 11500)
  assert.ok(!out.includes('#'), '不能残留 # 注释，否则客户端解析失败')
})

test('normalizeWireGuardConfig：重复的 AllowedIPs 去重', () => {
  const cfg = extractWireGuardConfig(REAL).replace(
    'AllowedIPs = 10.14.14.0/24',
    'AllowedIPs = 10.14.14.0/24,10.14.14.0/24'
  )
  const out = normalizeWireGuardConfig(cfg, '192.168.1.10', 11500)
  assert.match(out, /AllowedIPs = 10\.14\.14\.0\/24$/m)
  assert.equal(out.split('10.14.14.0/24').length - 1, 1, '同一个网段只能出现一次')
})

test('normalizeWireGuardConfig：网络地址 .0 修成可用主机地址 .2', () => {
  const out = normalizeWireGuardConfig(extractWireGuardConfig(REAL), '192.168.1.10', 11500)
  assert.match(out, /Address = 10\.14\.14\.2\/32/)
  assert.ok(!out.includes('10.14.14.0/32'), '.0 是网络地址，塞进客户端无法通信')
})

test('normalizeWireGuardConfig：Endpoint 换成本机可达地址', () => {
  const out = normalizeWireGuardConfig(extractWireGuardConfig(REAL), '192.168.1.10', 11500)
  assert.match(out, /Endpoint = 192\.168\.1\.10:11500/)
  assert.ok(!out.includes('0.0.0.0'), '0.0.0.0 在手机上指手机自己')
})

test('normalizeWireGuardConfig：没给 host 时丢掉 Endpoint 行', () => {
  const out = normalizeWireGuardConfig(extractWireGuardConfig(REAL), '', 11500)
  assert.ok(!out.includes('Endpoint'), '宁可留空让用户自己填，也不给 0.0.0.0')
})

test('clientAddressFrom：从 AllowedIPs 推断 /24 网段的主机地址', () => {
  assert.equal(clientAddressFrom(REAL), '10.14.14.2')
  assert.equal(clientAddressFrom(''), '10.14.14.2')
})

test('coreCommand：包含所有必需参数', () => {
  const cmd = coreCommand({
    networkName: 'dsh-abc',
    networkSecret: 'sec123',
    portalPort: 11011,
    peers: 'tcp://public.easytier.cn:11010',
  })
  assert.ok(cmd.startsWith('sudo easytier-core'))
  // 必须显式给 --ipv4：留空的话只转发不建 TUN，Virtual IP 为空，手机找不到电脑
  assert.ok(cmd.includes('--ipv4 10.14.14.1'), '缺 --ipv4 会导致电脑在虚拟网络里没有地址')
  assert.ok(cmd.includes('--network-name dsh-abc'))
  assert.ok(cmd.includes('--network-secret sec123'))
  // 格式必须是 wg://<监听>:<端口>/<客户端网段>，只写前半段会被 easytier 拒绝
  assert.ok(cmd.includes('--vpn-portal wg://0.0.0.0:11011/10.14.14.0/24'))
  // 这两个参数在 2.6.4 里不存在，写进去会报未知参数
  assert.ok(!cmd.includes('--vpn-portal-client'))
  assert.ok(!cmd.includes('--vpn-portal-private-key'))
  assert.ok(cmd.includes('-p tcp://public.easytier.cn:11010'))
})

test('randomNetwork：网络名带前缀且长度稳定', () => {
  const a = randomNetwork()
  const b = randomNetwork()
  assert.match(a.networkName, /^dsh-[a-z0-9]{8}$/)
  assert.match(a.networkSecret, /^[a-z0-9]{16}$/)
  // 两次不能一样（撞名会导致组网失败）
  assert.notEqual(a.networkName, b.networkName)
})

test('findEasytier：没装时返回 null，不抛错', async () => {
  const found = await findEasytier()
  assert.ok(found.core === null || typeof found.core === 'string')
  assert.ok(found.cli === null || typeof found.cli === 'string')
})

test('shadowrocketConf：skip-proxy 不能含 10.0.0.0/8', async () => {
  const { shadowrocketConf } = await import('../lib/easytier.js')
  const conf = shadowrocketConf({ socksHost: '192.168.1.10', socksPort: 1080 })
  const skipLine = conf.split('\n').find((l) => l.startsWith('skip-proxy'))
  assert.ok(skipLine)
  // 10.0.0.0/8 覆盖 10.14.14.0/24，留着就等于让客户端直连虚拟网络
  assert.ok(!skipLine.includes('10.0.0.0/8'), 'skip-proxy 含 10.0.0.0/8 会让虚拟网段被直连')
  assert.ok(!skipLine.includes('10.14.14'), '虚拟网段不能出现在 skip-proxy 里')
})

test('shadowrocketConf：有 SOCKS5 节点和指向它的规则', async () => {
  const { shadowrocketConf } = await import('../lib/easytier.js')
  const conf = shadowrocketConf({ socksHost: '192.168.1.10', socksPort: 1080 })
  assert.match(conf, /\[Proxy\]/)
  assert.match(conf, /EasyTier = socks5, 192\.168\.1\.10, 1080/)
  assert.match(conf, /\[Rule\]/)
  assert.match(conf, /IP-CIDR,10\.14\.14\.0\/24,EasyTier,no-resolve/)
})

test('shadowrocketConf：默认不劫持全部流量', async () => {
  const { shadowrocketConf } = await import('../lib/easytier.test.js').catch(() => ({}))
  const mod = await import('../lib/easytier.js')
  const conf = mod.shadowrocketConf({ socksHost: '10.0.0.1', socksPort: 1080 })
  // FINAL 必须是 DIRECT，否则用户所有上网流量都会绕到电脑
  assert.match(conf, /FINAL,DIRECT/)
})
