/**
 * dsh-pocket-ios 宿主入口。
 * UI 全部在 client/client.js；宿主只做一次存在性检查，缺少 dsh-pocket 时给出提示。
 */
export const name = 'dsh-pocket-ios'
export const inject = []

export function apply(ctx) {
  let hasPocket = false
  try {
    hasPocket = Boolean(ctx?.get?.('pocket'))
  } catch {}
  if (!hasPocket) {
    ctx?.logger?.info?.('dsh-pocket-ios: 未检测到 dsh-pocket 服务；请确认已安装并启用 dsh-pocket（手机访问）插件。')
  }
}
