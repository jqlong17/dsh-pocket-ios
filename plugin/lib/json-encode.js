/**
 * 插件自有 JSON 端点的响应编码：按需 gzip。
 *
 * 为什么只做「自有端点」：手机拉会话历史走的是 DSH 自己的 `/api/*`，
 * 插件只是 `proxyRes.pipe(res)` 转发。在代理层压缩需要缓冲整段响应，
 * 会破坏 SSE 流式输出（AI 回答要逐字吐）。所以压缩只做我们能控制的那部分。
 *
 * 客户端（iOS URLSession）会自动解压 gzip，无需改客户端。
 */
import { gzipSync } from 'node:zlib'

/** 低于这个大小不值得压（gzip 头 + 解压开销反而更大）。 */
export const COMPRESS_THRESHOLD = 1024

/**
 * 客户端是否接受 gzip。
 * @param {string|undefined} acceptEncoding
 */
export function wantsGzip(acceptEncoding) {
  if (typeof acceptEncoding !== 'string') return false
  return /\bgzip\b/i.test(acceptEncoding)
}

/**
 * 把 payload 编码成可写入的响应体。
 *
 * @param {unknown} payload 会被 JSON.stringify
 * @param {string|undefined} acceptEncoding 请求头
 * @param {{ threshold?: number, headers?: Record<string,string> }} [options]
 * @returns {{ body: Buffer|string, headers: Record<string,string>, compressed: boolean }}
 */
export function encodeJson(payload, acceptEncoding, options = {}) {
  const threshold = options.threshold ?? COMPRESS_THRESHOLD
  const raw = JSON.stringify(payload)
  const baseHeaders = {
    'content-type': 'application/json; charset=utf-8',
    ...(options.headers ?? {}),
  }
  // 先按字节算，汉字一个字符 3 字节，不能只看 length
  const bytes = Buffer.byteLength(raw)
  if (!wantsGzip(acceptEncoding) || bytes < threshold) {
    return { body: raw, headers: baseHeaders, compressed: false }
  }
  const gz = gzipSync(Buffer.from(raw))
  return {
    body: gz,
    headers: {
      ...baseHeaders,
      'content-encoding': 'gzip',
      vary: 'accept-encoding',
    },
    compressed: true,
  }
}
