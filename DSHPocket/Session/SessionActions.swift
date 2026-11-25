// 会话单条操作

import Foundation
import DSHKit

/// 会话的单条操作：重命名、选模型、置顶、归档、撤销归档、新建。
///
/// 边界（spec/12）：
/// - 只发请求 + 把结果写回 `SessionStore`，不做列表刷新编排（`reload` 由调用方给）；
/// - 不碰会话内容（messages/steps），也不管实时流；
/// - 错误统一交给 `reportError`，这里的职责是「发出去、把结果落到状态里」。
///
/// 为什么用 extension 而不是独立类型：见 spec/2026-11-12-2257 自审结论——
/// 这些方法读写的全是 ConnectionModel 的状态，自有状态为 0，独立类型只会带来 13 个闭包注入。
/// 文件拆开是为了控制行数；类型不拆，因为它本来就属于模型。
extension ConnectionModel {
    /// 会话操作的失败提示统一落到连接错误条（与原 Providers.reportError 行为一致）。
    @MainActor
    func reportActionError(_ message: String) { connection.errorMessage = message }

    @MainActor
    func rename(_ session: PocketSession, to rawTitle: String) async {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if !isDemoMode {
            do {
                _ = try await rpcClient.rpcAdapted("session/rename", args: ["request": [
                    "sessionId": session.sessionId,
                    "title": title
                ]])
            } catch {
                reportActionError("重命名失败：\(error.localizedDescription)")
                return
            }
        }
        let updated = PocketSession(
            sessionId: session.sessionId, updatedAt: session.updatedAt,
            running: session.running, blank: session.blank,
            title: title, cwd: session.cwd,
            origin: session.origin, parentSessionId: session.parentSessionId
        )
        if let index = sessionStore.sessions.firstIndex(where: { $0.sessionId == session.sessionId }) {
            sessionStore.sessions[index] = updated
        }
        if sessionStore.selected?.sessionId == session.sessionId {
            sessionStore.selected = updated
        }
    }

    /// 诊断用：读一次 describe、写一次 mutate，把每一步的真实形状记到 diag.log。
    /// 只由设置页的按钮触发——**不挂在启动路径上**（上次挂启动路径直接把 App 跑挂了）。
    @MainActor
    func diagnoseBusyEnterWrite() async {
        DiagFileLog.log("=== busyEnter 诊断开始 ===")
        do {
            let v = try await rpcClient.rpcAdapted(BusyEnterSetting.describeMethod, args: [:])
            let namespaces = v["namespaces"] as? [[String: Any]] ?? []
            DiagFileLog.log("describe: writable=\(v["writable"] ?? "?") 共 \(namespaces.count) 个 ns")
            for ns in namespaces where (ns["ns"] as? String)?.contains("conversation") == true {
                DiagFileLog.log("  命中 ns=\(ns["ns"] ?? "?") value=\(ns["value"] ?? [:]) hasSchema=\(ns["schema"] != nil)")
            }
            let names = namespaces.compactMap { $0["ns"] as? String }
            DiagFileLog.log("全部 ns: \(names.joined(separator: ", "))")
        } catch {
            DiagFileLog.log("describe 失败: \(error)")
        }

        do {
            let r = try await rpcClient.rpcAdapted(BusyEnterSetting.mutateMethod, args: [
                "ns": BusyEnterSetting.namespace,
                "ops": [["op": "set", "path": ["busyEnter"], "value": "queue"]]
            ])
            DiagFileLog.log("mutate 成功，返回 keys=\(r.keys.sorted()) value=\(r["value"] ?? [:])")
        } catch {
            DiagFileLog.log("mutate 失败: \(error)")
        }
        DiagFileLog.log("=== busyEnter 诊断结束 ===")
    }

    /// 读取「繁忙时发送方式」偏好。读不到就保持默认，**不报错打断用户**——
    /// 这是锦上添花的偏好，缺了不影响发送。
    @MainActor
    func loadBusyEnterPreference() async {
        guard !isDemoMode, !busyEnterLoaded else { return }
        do {
            let value = try await rpcClient.rpcAdapted(BusyEnterSetting.describeMethod, args: [:])
            let namespaces = value["namespaces"] as? [[String: Any]] ?? []
            if let mode = BusyEnterSetting.read(fromDescriptors: namespaces) {
                busyEnterPreference = mode
            }
            // 只有在请求成功时才置位：读失败允许下次进会话重试。
            busyEnterLoaded = true
        } catch {
            recordDiagnostic("读取发送方式偏好失败：\(error.localizedDescription)")
        }
    }

    /// 写入偏好。乐观更新 + 失败回滚——不能让开关停在「用户以为切了」的位置。
    @MainActor
    func setBusyEnterPreference(_ mode: PromptMode) async {
        guard !isDemoMode else {
            busyEnterPreference = mode
            return
        }
        let previous = busyEnterPreference
        busyEnterPreference = mode
        do {
            // 参数名必须是 `ns`：DSH 的签名是
            // mutate(ns: string, ops: SettingsPathOp[], expectedRevision?: number)
            // 写成 namespace 时 ns 为 undefined，服务端会报
            // `No configurable plugin entry "undefined"`。
            _ = try await rpcClient.rpcAdapted(BusyEnterSetting.mutateMethod, args: [
                "ns": BusyEnterSetting.namespace,
                "ops": BusyEnterSetting.writeOps(mode)
            ])
        } catch {
            busyEnterPreference = previous
            // 失败必须留痕：只弹窗的话，事后完全无法定位（这次就卡在这）。
            DiagFileLog.log("busyEnter-write-FAILED ns=\(BusyEnterSetting.namespace) mode=\(mode.rawValue) error=\(error)")
            reportActionError("切换发送方式失败：\(error.localizedDescription)")
        }
    }

    /// 换了一台 DSH 之后必须失效：模型清单**是每台机器各自的配置**，
    /// 不清空就会继续显示上一台机器的模型（2026-11-25 用户反馈「为什么只有三个模型」）。
    @MainActor
    func invalidateModelCatalog() {
        modelGroups = []
        selectedModelLabel = nil
        recordDiagnostic("模型清单已失效（切换机器）")
    }

    @MainActor
    func loadModelCatalog() async {
        guard !isDemoMode else { return }
        do {
            let value = try await rpcClient.rpcAdapted("session/modelCatalog", args: [:])
            let groups = value["groups"] as? [[String: Any]] ?? []
            let parsed = groups.compactMap { group -> ModelGroup? in
                guard let id = group["id"] as? String,
                      let name = group["name"] as? String else { return nil }
                let models = (group["models"] as? [[String: Any]] ?? []).compactMap { item -> ModelOption? in
                    guard let model = item["id"] as? String else { return nil }
                    // reasoning 是可选块：只有提供方公布强度的模型才有。
                    let reasoning = item["reasoning"] as? [String: Any]
                    let efforts = (reasoning?["efforts"] as? [[String: Any]] ?? []).compactMap { raw -> ReasoningOption? in
                        guard let eid = raw["id"] as? String else { return nil }
                        return ReasoningOption(
                            id: eid,
                            name: raw["name"] as? String ?? eid,
                            detail: raw["description"] as? String
                        )
                    }
                    return ModelOption(provider: id, model: model,
                                       name: item["name"] as? String ?? model,
                                       reasoningEfforts: efforts,
                                       defaultEffort: reasoning?["defaultEffort"] as? String)
                }
                return ModelGroup(id: id, name: name, models: models)
            }
            modelGroups = parsed
            guard selectedModelLabel == nil,
                  let defaultSel = value["default"] as? [String: Any],
                  let provider = defaultSel["provider"] as? String,
                  let model = defaultSel["model"] as? String else { return }
            let label = parsed.first { $0.id == provider }?
                .models.first { $0.model == model }?.name ?? model
            selectedModelLabel = label
        } catch {
            recordDiagnostic("模型列表加载失败：\(error.localizedDescription)")
        }
    }

    @MainActor
    /// 切换模型。`reasoningEffort` 只在模型公布强度时传；传 nil 表示「提供方默认」。
    func selectModel(_ option: ModelOption, reasoningEffort: String? = nil) async {
        guard let session = sessionStore.selected else { return }
        if isDemoMode {
            selectedModelLabel = option.name
            return
        }
        var request: [String: Any] = [
            "sessionId": session.sessionId,
            "provider": option.provider,
            "model": option.model
        ]
        // 省略等于用提供方默认，所以 nil 时**不要**塞这个键。
        if let reasoningEffort { request["reasoningEffort"] = reasoningEffort }
        do {
            _ = try await rpcClient.rpcAdapted("session/selectModel", args: ["request": request])
            selectedModelLabel = option.name
            selectedReasoningLabel = option.reasoningEfforts
                .first { $0.id == reasoningEffort }?.name
        } catch {
            reportActionError("切换模型失败：\(error.localizedDescription)")
        }
    }

    @MainActor
    func dismissArchiveUndo() {
        lastArchivedSession = nil
    }

    /// 撤销最近一次归档。
    @MainActor
    func undoArchive() async {
        guard let session = lastArchivedSession else { return }
        lastArchivedSession = nil
        if isDemoMode {
            sessionStore.archivedSessionIds.remove(session.sessionId)
            await loadSessions()
            return
        }
        do {
            _ = try await rpcClient
                .rpcAdapted("workspace/unarchiveSession", args: ["request": ["sessionId": session.sessionId]])
            sessionStore.archivedSessionIds.remove(session.sessionId)
            await loadSessions()
        } catch {
            reportActionError("撤销归档失败：\(error.localizedDescription)")
        }
    }

    @MainActor
    func togglePin(_ session: PocketSession) async {
        // 无前置条件
        let store = sessionStore
        let pinned = store.pinnedSessionIds.contains(session.sessionId)
        if isDemoMode {
            if pinned {
                store.pinnedSessionIds.removeAll { $0 == session.sessionId }
            } else {
                store.pinnedSessionIds.insert(session.sessionId, at: 0)
            }
            return
        }
        do {
            let endpoint = pinned ? "workspace/unpinSession" : "workspace/pinSession"
            let value = try await rpcClient
                .rpcAdapted(endpoint, args: ["request": ["sessionId": session.sessionId]])
            if let list = value["pinnedSessionIds"] as? [String] {
                store.pinnedSessionIds = list
            } else if pinned {
                store.pinnedSessionIds.removeAll { $0 == session.sessionId }
            } else {
                store.pinnedSessionIds.insert(session.sessionId, at: 0)
            }
        } catch {
            reportActionError("置顶失败：\(error.localizedDescription)")
        }
    }

    /// 归档会话（从列表移除，桌面端同步隐藏）。
    @MainActor
    func archive(_ session: PocketSession) async {
        // 无前置条件
        let store = sessionStore
        if isDemoMode {
            store.sessions.removeAll { $0.sessionId == session.sessionId }
            store.archivedSessionIds.insert(session.sessionId)
            store.pinnedSessionIds.removeAll { $0 == session.sessionId }
            return
        }
        do {
            let value = try await rpcClient.rpcAdapted("workspace/archiveSession", args: ["request": [
                "sessionId": session.sessionId,
                "stopActivity": false
            ]])
            if let ids = value["archivedSessionIds"] as? [String] {
                store.archivedSessionIds = Set(ids)
            } else {
                store.archivedSessionIds.insert(session.sessionId)
            }
            store.sessions.removeAll { $0.sessionId == session.sessionId }
            store.pinnedSessionIds.removeAll { $0 == session.sessionId }
            lastArchivedSession = session
            if store.selected?.sessionId == session.sessionId { store.selected = nil }
        } catch {
            reportActionError("归档失败：\(error.localizedDescription)")
        }
    }

    /// 新建会话。
    ///
    /// - Parameter workspaceId: 指定工作区；不传时落默认工作区（与旧行为一致）。
    @MainActor
    func createSession(in workspaceId: String? = nil) async {
        do {
            var request: [String: Any] = [:]
            if let workspaceId, !workspaceId.isEmpty {
                request["workspaceId"] = workspaceId
            } else if let initialized = try? await rpcClient.rpcAdapted("workspace/initializeDefault", args: [:]),
                      let workspace = initialized["workspace"] as? [String: Any],
                      let fallbackId = workspace["workspaceId"] as? String {
                request["workspaceId"] = fallbackId
            }
            let value = try await rpcClient
                .rpcAdapted("session/create", args: ["request": request])
            guard let id = value["sessionId"] as? String else { throw ConnectionError.invalidPayload }
            let session = PocketSession(sessionId: id, updatedAt: Date().timeIntervalSince1970,
                                        running: false, blank: true)
            await loadSessions()
            if !sessionStore.sessions.contains(where: { $0.sessionId == id }) {
                sessionStore.sessions.insert(session, at: 0)
            }
            open(session)
            // 列表页是靠 NavigationLink(value:) 推进导航栈的，代码里创建不会自动跳转，
            // 必须显式把新会话压栈，否则用户会停在列表页等一个不存在的点击。
            sessionStore.navigationPath = [session]
        } catch {
            // 断网与真失败要分开说：把 URLError 的英文原文丢给用户（"The Internet connection
            // appears to be offline."）既打断操作又没告诉他该做什么。
            reportActionError(Self.isTransientNetworkError(error)
                              ? L10n.t("现在没网，连上之后再试")
                              : "\(L10n.t("无法创建会话"))：\(error.localizedDescription)")
        }
    }
}
