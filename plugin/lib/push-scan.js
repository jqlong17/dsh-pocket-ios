/**
 * 纯判定逻辑：从会话事件里决定「该不该给这次 turn/end 发推送」。
 *
 * 为什么单独成文件：这一段是「通知轰炸」的唯一防线，也是最容易写错的地方
 * （谁先谁后、可见状态是否过期、冷却期），必须能脱离 IO 单测。
 */

/** 一轮回复结束后，同一会话至少隔这么久才允许再推一次。 */
export const DEFAULT_COOLDOWN_MS = 60_000;

/** 可见状态的有效期：App 被杀或锁屏后，它不该继续压制推送。 */
export const VISIBLE_STATE_TTL_MS = 30_000;

/**
 * @param {object} input
 * @param {string} input.sessionId  本次要判定的是哪个会话
 * @param {Array<{type: string, time?: number}>} input.events
 *        会话事件（时间升序），至少包含 type；用于找最后一个 turn/end 与它之后的用户消息
 * @param {string|null} input.visibleSessionId  App 上报的「当前可见会话」
 * @param {boolean} input.appActive              App 是否在前台
 * @param {number|null} input.visibleAt          可见状态的上报时刻（ms）
 * @param {number|null} input.lastNotifiedAt     上次给这个会话推送的时刻（ms）
 * @param {number} [input.now]                   当前时刻（ms），测试注入
 * @returns {{notify: boolean, reason: string}}
 */
export function shouldNotify({
  sessionId = null,
  events,
  visibleSessionId = null,
  appActive = false,
  visibleAt = null,
  lastNotifiedAt = null,
  now = Date.now(),
  cooldownMs = DEFAULT_COOLDOWN_MS,
} = {}) {
  if (!Array.isArray(events) || events.length === 0) {
    return { notify: false, reason: 'no-events' };
  }

  // 从后往前找最后一个 turn/end
  let turnEndIndex = -1;
  for (let i = events.length - 1; i >= 0; i -= 1) {
    if (events[i]?.type === 'turn/end') {
      turnEndIndex = i;
      break;
    }
  }
  if (turnEndIndex < 0) {
    return { notify: false, reason: 'no-turn-end' };
  }

  // 只看「真实用户消息」：系统注入（runtime-context / skill-catalog 等）
  // 也是 user/message，误判会导致永远不推（本仓库在「消息来源」上踩过同样的坑）。
  const userRepliedAfter = events
    .slice(turnEndIndex + 1)
    .some((event) =>
      event?.type === 'user/message' && event?.data?.source?.kind === 'user');

  if (userRepliedAfter) {
    return { notify: false, reason: 'user-already-replied' };
  }

  // 前台正在看**这个**会话才抑制。
  // 必须比较 sessionId：只看「有没有可见会话」会把其他会话的推送也一起压掉
  // （测试抓到的真 bug：看 A 时 B 完成，结果不推）。
  if (appActive && visibleSessionId && sessionId && visibleSessionId === sessionId) {
    const fresh = typeof visibleAt === 'number' && (now - visibleAt) <= VISIBLE_STATE_TTL_MS;
    if (fresh) {
      return { notify: false, reason: 'user-viewing' };
    }
  }

  // 冷却期：同一会话刚推过
  if (typeof lastNotifiedAt === 'number' && (now - lastNotifiedAt) < cooldownMs) {
    return { notify: false, reason: 'cooldown' };
  }

  return { notify: true, reason: 'ok' };
}

/**
 * 从会话事件里取「显示用的标题上下文」：最后一个 assistant 文本的片段。
 * 取不到就返回空串（推送正文回退到「等你回复」）。
 */
export function lastAssistantSnippet(events, maxLength = 60) {
  if (!Array.isArray(events)) return '';
  for (let i = events.length - 1; i >= 0; i -= 1) {
    const event = events[i];
    if (event?.type !== 'assistant/message') continue;
    const content = event?.data?.content;
    if (!Array.isArray(content)) continue;
    for (const block of content) {
      if (block?.type !== 'text' || typeof block.text !== 'string') continue;
      const text = block.text.replace(/\s+/g, ' ').trim();
      if (text) {
        return text.length > maxLength ? `${text.slice(0, maxLength)}…` : text;
      }
    }
  }
  return '';
}
