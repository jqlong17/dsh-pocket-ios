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
                    return ModelOption(provider: id, model: model,
                                       name: item["name"] as? String ?? model)
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
    func selectModel(_ option: ModelOption) async {
        guard let session = sessionStore.selected else { return }
        if isDemoMode {
            selectedModelLabel = option.name
            return
        }
        do {
            _ = try await rpcClient.rpcAdapted("session/selectModel", args: ["request": [
                "sessionId": session.sessionId,
                "provider": option.provider,
                "model": option.model
            ]])
            selectedModelLabel = option.name
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

    @MainActor
    func createSession() async {
        // 无前置条件
        do {
            var request: [String: Any] = [:]
            if let initialized = try? await rpcClient.rpcAdapted("workspace/initializeDefault", args: [:]),
               let workspace = initialized["workspace"] as? [String: Any],
               let workspaceId = workspace["workspaceId"] as? String {
                request["workspaceId"] = workspaceId
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
