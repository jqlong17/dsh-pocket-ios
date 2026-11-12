// ConnectionState

import Foundation
import Observation

/// 连接配置与状态机：地址、PIN、连接中/已连/失败提示。
///
/// 边界（重要）：
/// - **只放「连接页会变的事实」**，不放网络实现（URLSession、socket 都在别处）。
/// - 其它模块（诊断、发件箱、会话）通过 `ConnectionModel` 的转发读它，不直接依赖本类型，
///   这样「改连接不会碰到发送」的边界才成立（spec/12）。
/// - 持久化仍在调用方做（`+Connect` 里保存地址），本类型不碰 UserDefaults，
///   否则单独测试时会被真实偏好污染。
@Observable
final class ConnectionState {
    /// 服务器地址（`http(s)://host:port`）。启动时从偏好恢复，修改后由调用方落盘。
    var serverAddress: String

    /// 访问 PIN。只存在内存：不落盘，退出即失效。
    var pin = ""

    var isConnecting = false
    var isConnected = false
    /// 启动恢复流程是否已结束（成功、失败、无地址都算结束）。
    /// 视图靠它区分「还没确定」与「确定未连接」——前者不能显示连接页，否则启动会闪一下。
    var hasFinishedRestore = false
    /// 连接失败的提示文案；成功或重试时清空。
    var errorMessage: String?
    /// 扫到/输入的地址不可用，界面要给「重新扫码」入口。
    var addressNeedsRescan = false

    init(serverAddress: String) {
        self.serverAddress = serverAddress
    }
}
