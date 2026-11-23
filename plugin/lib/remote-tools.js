// 跨机器 DSH 的工具：列出对方会话、向对方会话发消息并等回复。
//
// 为什么做成工具而不是界面：@ 选择器要么接管宿主的 composer（改不了发送目标），
// 要么自己画一套聊天 UI（ds-bot 就是这么做的，代价是五万行客户端 + 大量 CSS 覆盖）。
// 工具不需要界面：用户在对话里说「发给阿里云的 XX 会话」，助手直接调用即可。
import { listPeerSessions, sayToPeer } from './peer-client.js'

/** 工具定义尽量简单：描述行为与返回，把参数规则放在参数上。 */
// defineTool 要求每个工具声明 output，缺了会在 register 时抛
// "Cannot read properties of undefined (reading 'render')"。
// 两个工具都返回一段给人读的文本，所以共用这一份声明。
const TEXT_OUTPUT = {
  schema: { type: 'string' },
  render: (_args, value) => [{ type: 'text', text: String(value) }],
}

function toolDefs({ readPeers }) {
  const HOST_PARAM = {
    type: 'string',
    description: '节点名或地址。只有一个节点时可省略。',
  }
  const SESSION_PARAM = {
    type: 'string',
    description: '目标会话：标题的一部分或会话 id。省略则取该节点最近活动的会话。',
  }

  return [
    {
      name: 'remote_dsh_sessions',
      description: '列出其它 DSH 节点上的会话（标题、最近活动时间），用于确定要把消息发给哪个会话。',
      parameters: { host: HOST_PARAM },
      output: TEXT_OUTPUT,
      async execute(args) {
        const peers = await readPeers()
        if (!peers.length) return '还没有配置其它 DSH 节点。请让用户在「设置 → 手机访问 → 其它 DSH 节点」里添加。'
        const target = resolvePeer(peers, args?.host)
        if (!target) return `没有找到节点「${args?.host ?? ''}」。可用：${peers.map((p) => p.name || p.id).join('、')}`
        const sessions = await listPeerSessions(target.address)
        if (!sessions.length) return `${target.name || target.id} 上没有会话。`
        const lines = sessions.map((s, i) => {
          const when = s.updatedAt ? new Date(s.updatedAt).toLocaleString('zh-CN', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' }) : '未知'
          return `${i + 1}. ${s.title || '(无标题)'} · ${when} · ${s.sessionId}`
        })
        return `${target.name || target.id} 的会话：\n${lines.join('\n')}`
      },
    },
    {
      name: 'remote_dsh_say',
      description: '向另一个 DSH 上的某个会话发送一条消息，等它回复后把回复内容返回。',
      parameters: {
        host: HOST_PARAM,
        session: SESSION_PARAM,
        message: { type: 'string', required: true, description: '要发过去的内容；对方看不到当前对话，所以需要自包含。' },
        timeoutSeconds: { type: 'number', description: '等待回复的上限，默认 120 秒。' },
      },
      output: TEXT_OUTPUT,
      async execute(args) {
        const peers = await readPeers()
        if (!peers.length) return '还没有配置其它 DSH 节点。'
        const target = resolvePeer(peers, args?.host)
        if (!target) return `没有找到节点「${args?.host ?? ''}」。可用：${peers.map((p) => p.name || p.id).join('、')}`

        const sessions = await listPeerSessions(target.address)
        const picked = resolveSession(sessions, args?.session)
        if (!picked) {
          const hint = sessions.slice(0, 8).map((s) => `· ${s.title || s.sessionId}`).join('\n')
          return `在 ${target.name || target.id} 上没找到会话「${args?.session ?? ''}」。可选：\n${hint}`
        }

        const timeoutMs = Math.max(10000, Math.min(600000, Number(args?.timeoutSeconds ?? 120) * 1000))
        const result = await sayToPeer(target.address, {
          sessionId: picked.sessionId,
          text: String(args.message ?? ''),
          timeoutMs,
        })
        const where = `${target.name || target.id} · ${picked.title || picked.sessionId.slice(0, 16)}`
        if (!result.reply) return `已发送到 ${where}，但 ${Math.round(result.elapsedMs / 1000)} 秒内没收到回复。`
        return `${where} 回复（${Math.round(result.elapsedMs / 1000)} 秒）：\n${result.reply}`
      },
    },
  ]
}

function resolvePeer(peers, wanted) {
  const key = String(wanted ?? '').trim().toLowerCase()
  if (!key) return peers.length === 1 ? peers[0] : null
  return peers.find((p) =>
    [p.id, p.name, p.address].filter(Boolean).some((v) => String(v).toLowerCase() === key)
  ) || peers.find((p) =>
    [p.id, p.name, p.address].filter(Boolean).some((v) => String(v).toLowerCase().includes(key))
  ) || null
}

function resolveSession(sessions, wanted) {
  const key = String(wanted ?? '').trim()
  if (!key) {
    // 省略时取最近活动的会话：最符合「接着说」的直觉。
    return [...sessions].sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0))[0] ?? null
  }
  const lower = key.toLowerCase()
  return sessions.find((s) => s.sessionId === key)
    || sessions.find((s) => (s.title || '').toLowerCase() === lower)
    || sessions.find((s) => (s.title || '').toLowerCase().includes(lower))
    || null
}

/**
 * 把工具注册到当前的 ctx 上。
 *
 * 依据官方 @deepseek-ai/dsh-tools 文档：`ctx.tools.register(defineTool({...}))`
 * 直接注册即可，注册表会自动把 schema 送进系统提示词组装，**不需要**按 Agent 注册。
 *
 * `defineTool` 用动态 import：它由宿主提供（插件自己不依赖它，ds-bot 也一样），
 * 静态 import 会在解析失败时把整个插件带崩。拿不到就用普通对象兜底，
 * 至多工具不出现，不会影响面板和已有功能。
 */
export async function registerRemoteTools(ctx, { readPeers, log }) {
  const register = ctx?.tools?.register
  if (typeof register !== 'function') {
    await log?.('tools 不可用，跨机器工具未注册')
    return
  }

  let defineTool = null
  try {
    const mod = await import('@deepseek-ai/dsh-tools')
    if (typeof mod?.defineTool === 'function') defineTool = mod.defineTool
  } catch (error) {
    await log?.(`defineTool 解析失败，改用普通对象: ${error?.code ?? error?.message ?? error}`)
  }

  const defs = toolDefs({ readPeers })
  let ok = 0
  for (const def of defs) {
    try {
      const built = defineTool ? defineTool(def) : def
      register.call(ctx.tools, built)
      ok += 1
    } catch (error) {
      await log?.(`注册工具 ${def.name} 失败: ${error?.message ?? error}`)
    }
  }
  await log?.(`跨机器工具注册完成: ${ok}/${defs.length}（defineTool=${defineTool ? 'yes' : 'no'}）`)
}
