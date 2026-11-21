/**
 * 连接标签：给每条 iOS 发来的消息记一笔「它到达时的真实连接」。
 *
 * 为什么需要：网络类型、链路（局域网/Tailscale）、RTT 现在散在遥测、lsof、
 * tailscale status 三处，**没有一处和具体消息绑定**。用户问「我刚才那条怎么连进来的」，
 * 只能靠时间戳猜。
 *
 * 三条设计约束：
 * 1. **纯函数**：不读文件、不发请求，全部输入由调用方给，便于单测。
 * 2. **不瞎猜**：快照过期或缺失时标 `unknown`，绝不沿用旧值（旧值会误导归因）。
 * 3. **不带凭证**：只记网络类型与地址形态，不记 token。
 */

/** 快照有效期：App 锁屏后 telemetry 会停，旧状态不能用来标新消息。 */
export const SNAPSHOT_TTL_MS = 60_000;

/** iOS App 发出的消息末尾带两个不可见分隔符（见 AGENTS.md §3.8）。 */
const IOS_MARKER = '\u2063\u2063';

/**
 * 从 App 的遥测 payload 里提取连接快照。
 * @param {object} payload /telemetry 的请求体
 * @param {number} now
 * @returns {{at:number, network:string, path:string, rttMs:number|null, reachable:boolean}}
 */
export function snapshotFromTelemetry(payload, now = Date.now()) {
  const network = typeof payload?.probeNetwork === 'string' ? payload.probeNetwork : 'unknown';
  const probes = Array.isArray(payload?.probes) ? payload.probes : [];
  const current = probes.find((probe) => probe?.isCurrent === true);

  if (!current) {
    // 没有「当前连接」的探测结果：标记 unknown，不假装知道。
    return { at: now, network, path: 'unknown', rttMs: null, reachable: false };
  }
  return {
    at: now,
    network,
    path: classifyAddress(current.address),
    rttMs: typeof current.rttMs === 'number' ? current.rttMs : null,
    reachable: current.ok === true,
  };
}

/**
 * 把地址归类成人能一眼看懂的方式。
 *
 * 只区分三类：局域网 / Tailscale / 其它公网。
 * Cloudflare 与 EasyTier 都归到「公网」，因为它们对排查的结论一致（走隧道/出公网）。
 */
export function classifyAddress(address) {
  if (typeof address !== 'string' || address.length === 0) return 'unknown';
  let host = '';
  try {
    host = new URL(address).hostname.toLowerCase();
  } catch {
    host = address.toLowerCase();
  }
  if (host.endsWith('.ts.net')) return 'tailscale';
  if (host.endsWith('.trycloudflare.com')) return 'cloudflare';
  if (host === 'localhost' || host.endsWith('.local')) return 'lan';
  const parts = host.split('.').map((part) => Number(part));
  if (parts.length === 4 && parts.every((n) => Number.isInteger(n) && n >= 0 && n <= 255)) {
    const [a, b] = parts;
    if (a === 127 || a === 10 || (a === 192 && b === 168) || (a === 172 && b >= 16 && b <= 31)) {
      return 'lan';
    }
    return 'public';
  }
  return 'public';
}

/** 快照是否还在有效期内。过期就不该拿来标新消息。 */
export function isSnapshotFresh(snapshot, now = Date.now(), ttlMs = SNAPSHOT_TTL_MS) {
  if (!snapshot || typeof snapshot.at !== 'number') return false;
  return now - snapshot.at <= ttlMs;
}

/** 消息正文是否带 iOS 标记。 */
export function isIOSMessage(text) {
  return typeof text === 'string' && text.endsWith(IOS_MARKER);
}

/**
 * 从一条 user/message 事件里提取要记的信息。
 * 不是真人消息（注入类）或没有 rpcId 时返回 null。
 */
export function messageDescriptor(event) {
  if (!event || event.type !== 'user/message') return null;
  const source = event.data?.source;
  if (source?.kind !== 'user') return null;
  const rpcId = typeof source?.rpcId === 'string' ? source.rpcId : '';
  if (!rpcId) return null;

  const content = Array.isArray(event.data?.content) ? event.data.content : [];
  const text = content.find((block) => block?.type === 'text')?.text ?? '';
  return {
    rpcId,
    seq: typeof event.seq === 'number' ? event.seq : null,
    messageAt: typeof event.time === 'number' ? event.time : null,
    ios: isIOSMessage(text),
  };
}

/**
 * 组装一行标签。
 *
 * `snapshot` 可以是 null / 过期——那时网络与路径都标 unknown，
 * 而不是留空：留空会被下游当成「没记」，unknown 明确表示「记了但当时不知道」。
 */
export function buildTag({ sessionId, descriptor, snapshot, now = Date.now() }) {
  if (!descriptor) return null;
  const fresh = isSnapshotFresh(snapshot, now);
  return {
    recordedAt: new Date(now).toISOString(),
    rpcId: descriptor.rpcId,
    sessionId: typeof sessionId === 'string' ? sessionId : '',
    seq: descriptor.seq,
    messageAt: descriptor.messageAt,
    ios: descriptor.ios,
    network: fresh ? snapshot.network : 'unknown',
    path: fresh ? snapshot.path : 'unknown',
    rttMs: fresh ? snapshot.rttMs : null,
    reachable: fresh ? snapshot.reachable : false,
    snapshotAgeMs: fresh ? Math.max(0, now - snapshot.at) : null,
  };
}
