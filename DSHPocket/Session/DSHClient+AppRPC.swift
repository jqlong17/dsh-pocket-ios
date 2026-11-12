// DSHClient+AppRPC

import Foundation
import DSHKit

/// App 侧的 RPC 调用入口：**唯一职责是把 DSHKit 的错误类型适配成界面认识的类型**。
///
/// 为什么要有它（spec/13）：
/// - 协议实现（envelope / URL / 超时 / 状态码）只允许存在于 DSHKit，这里一行协议都不写；
/// - UI 与旧代码判断的是 `ConnectionError`（例如 `.server(401)` 触发重新登录），
///   直接抛 `DSHError` 会让这些判断全部失效；
/// - 传输层错误（`URLError`）**原样抛出**，`isTransientNetworkError` 的重试判断才继续有效。
///
/// 也就是说：这是错误适配器，不是第二套 RPC。删掉它只会让 UI 改判错误类型，不会改变协议行为。
extension DSHClient {
    func rpcAdapted(_ endpoint: String, args: [String: Any],
                    timeout: TimeInterval = 20) async throws -> [String: Any] {
        do {
            return try await rpc(method: endpoint, args: args, timeout: timeout)
        } catch let error as DSHError {
            throw ConnectionError.from(error, address: baseURL.absoluteString)
        }
    }

    /// 带重试的适配版：同一 rpcId 贯穿重试，仅瞬时错误重试（策略在 DSHKit）。
    func rpcWithRetryAdapted(_ endpoint: String, args: [String: Any],
                             attempts: Int = 3,
                             timeout: TimeInterval = 20) async throws -> [String: Any] {
        do {
            return try await rpcWithRetry(method: endpoint, args: args,
                                          attempts: attempts, timeout: timeout)
        } catch let error as DSHError {
            throw ConnectionError.from(error, address: baseURL.absoluteString)
        }
    }
}
