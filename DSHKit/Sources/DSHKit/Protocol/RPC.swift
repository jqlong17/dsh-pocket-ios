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
    public static func value(from data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DSHError.invalidPayload
        }
        if let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String
            throw DSHError.server(status: (error["status"] as? NSNumber)?.intValue ?? 0, message: message)
        }
        guard let result = object["result"] as? [String: Any],
              let value = result["value"] as? [String: Any] else { throw DSHError.invalidPayload }
        return value
    }
}
