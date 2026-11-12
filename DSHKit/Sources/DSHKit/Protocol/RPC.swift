import Foundation

/// `POST /api/<method>` 的请求封装（用例 P03）。
public struct RPCRequest {
    public let method: String
    public let rpcId: UUID
    public let args: [String: Any]

    public init(method: String, rpcId: UUID = UUID(), args: [String: Any] = [:]) {
        self.method = method
        self.rpcId = rpcId
        self.args = args
    }

    /// 编码为 DSH 的 client-request envelope：`{type, rpcId, method, payload:{args}}`。
    public func encoded() throws -> Data {
        let body: [String: Any] = [
            "type": "client-request",
            "rpcId": rpcId.uuidString,
            "method": method,
            "payload": ["args": args]
        ]
        guard JSONSerialization.isValidJSONObject(body) else { throw DSHError.invalidPayload }
        return try JSONSerialization.data(withJSONObject: body, options: [])
    }

    /// 从响应体提取 `result.value`。
    ///
    /// 失败有两种形状，都要认：
    /// 1. 顶层 `error`（传输/鉴权层失败）；
    /// 2. `result.ok == false` + `result.error.message`（业务失败）。
    /// 只认第一种会把业务失败当成成功——这是收口两套 RPC 时最容易漏的一条。
    public static func value(from data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DSHError.invalidPayload
        }
        if let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String
            throw DSHError.server(status: (error["status"] as? NSNumber)?.intValue ?? 0, message: message)
        }
        guard let result = object["result"] as? [String: Any] else { throw DSHError.invalidPayload }
        if (result["ok"] as? Bool) == false {
            let detail = result["error"] as? [String: Any]
            let message = detail?["message"] as? String
            let status = (detail?["status"] as? NSNumber)?.intValue ?? 0
            throw DSHError.server(status: status, message: message)
        }
        guard let value = result["value"] as? [String: Any] else { throw DSHError.invalidPayload }
        return value
    }
}
