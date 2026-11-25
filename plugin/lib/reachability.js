/**
 * 「地址是否已经对外可访问」的判定。
 *
 * 背景：Cloudflare quick 隧道建好后，官方提示 "it may take some time to be reachable"。
 * 实测首次扫到刚建好的地址会失败一次（App 显示「这次配对没成功」），等十几秒再扫就好。
 * 所以在把二维码交给用户之前，先探一次：探不通就让他等，而不是给一个必然失败的码。
 */

/** 这些状态码说明「已经能连到服务」，401/403 是插件鉴权，属于正常。 */
export function isReachableStatus(status) {
  return status === 200 || status === 401 || status === 403
}

/**
 * 用 HEAD 探测一个地址；任何非 0 的 HTTP 响应都算「网络层通了」。
 *
 * @param {string} url
 * @param {{ timeoutMs?: number, fetchImpl?: Function }} [options]
 * @returns {Promise<{ ok: boolean, status: number|null, error?: string }>}
 */
export async function probe(url, options = {}) {
  const timeoutMs = options.timeoutMs ?? 2500
  const fetchImpl = options.fetchImpl ?? globalThis.fetch
  if (typeof fetchImpl !== 'function') return { ok: false, status: null, error: 'no-fetch' }
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), timeoutMs)
  try {
    const res = await fetchImpl(url, { method: 'HEAD', signal: controller.signal, redirect: 'manual' })
    const status = typeof res?.status === 'number' ? res.status : null
    return { ok: isReachableStatus(status), status }
  } catch (error) {
    return { ok: false, status: null, error: String(error?.message ?? error) }
  } finally {
    clearTimeout(timer)
  }
}
