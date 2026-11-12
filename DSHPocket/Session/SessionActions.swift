// SessionActions

import Foundation
import DSHKit

/// 会话的单条操作：重命名、选模型、置顶、归档、撤销归档、新建。
///
/// 边界（spec/12）：
/// - 只发请求 + 把结果写回 `SessionStore`，不做列表刷新编排（`reload` 由调用方给）；
/// - 不碰会话内容（messages/steps），也不管实时流；
/// - 错误统一交给 `reportError`，这里的职责是「发出去、把结果落到状态里」。
///
/// 为什么从 ConnectionModel 搬出来：这六件事各自独立，混在 650 行的 extension 里
/// 改一个要读一整段；抽出来之后每个操作自成一体，失败也只影响自己那条路径。
final class SessionActions {
    struct Providers {
        /// 当前可用的 RPC 客户端。
        var client: () throws -> DSHClient
        /// 会话数据的所有者。
        var store: SessionStore
        var isDemoMode: () -> Bool
        /// 操作失败时给用户的提示。
        var reportError: (String) -> Void
        var record: (String) -> Void
        /// 列表刷新（撤销归档、新建会话后需要）。
        var reload: @MainActor () async -> Void
        /// 模型目录的状态（列表页/会话页共用）。
        var modelGroups: () -> [ModelGroup]
        var setModelGroups: ([ModelGroup]) -> Void
        var selectedModelLabel: () -> String?
        var setSelectedModelLabel: (String?) -> Void
        /// 最近一次归档（用于「撤销」）。
        var lastArchived: () -> PocketSession?
        var setLastArchived: (PocketSession?) -> Void
        /// 新建会话成功后打开它。
        var open: (PocketSession) -> Void
    }

    var providers: Providers?

    @MainActor
    func rename(_ session: PocketSession, to rawTitle: String) async {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let providers else { return }
        if !providers.isDemoMode() {
            do {
                _ = try await providers.client().rpcAdapted("session/rename", args: ["request": [
                    "sessionId": session.sessionId,
                    "title": title
                ]])
            } catch {
                providers.reportError("重命名失败：\(error.localizedDescription)")
                return
            }
        }
        let updated = PocketSession(
            sessionId: session.sessionId, updatedAt: session.updatedAt,
            running: session.running, blank: session.blank,
            title: title, cwd: session.cwd,
            origin: session.origin, parentSessionId: session.parentSessionId
        )
        if let index = providers.store.sessions.firstIndex(where: { $0.sessionId == session.sessionId }) {
            providers.store.sessions[index] = updated
        }
        if providers.store.selected?.sessionId == session.sessionId {
            providers.store.selected = updated
        }
    }

    @MainActor
    func loadModelCatalog() async {
        guard let providers, !providers.isDemoMode() else { return }
        do {
            let value = try await providers.client().rpcAdapted("session/modelCatalog", args: [:])
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
            providers.setModelGroups(parsed)
            guard providers.selectedModelLabel() == nil,
                  let defaultSel = value["default"] as? [String: Any],
                  let provider = defaultSel["provider"] as? String,
                  let model = defaultSel["model"] as? String else { return }
            let label = parsed.first { $0.id == provider }?
                .models.first { $0.model == model }?.name ?? model
            providers.setSelectedModelLabel(label)
        } catch {
            providers.record("模型列表加载失败：\(error.localizedDescription)")
        }
    }

    @MainActor
    func selectModel(_ option: ModelOption) async {
        guard let providers, let session = providers.store.selected else { return }
        if providers.isDemoMode() {
            providers.setSelectedModelLabel(option.name)
            return
        }
        do {
            _ = try await providers.client().rpcAdapted("session/selectModel", args: ["request": [
                "sessionId": session.sessionId,
                "provider": option.provider,
                "model": option.model
            ]])
            providers.setSelectedModelLabel(option.name)
        } catch {
            providers.reportError("切换模型失败：\(error.localizedDescription)")
        }
    }

    @MainActor
    func dismissArchiveUndo() {
        providers?.setLastArchived(nil)
    }

    /// 撤销最近一次归档。
    @MainActor
    func undoArchive() async {
        guard let providers, let session = providers.lastArchived() else { return }
        providers.setLastArchived(nil)
        if providers.isDemoMode() {
            providers.store.archivedSessionIds.remove(session.sessionId)
            await providers.reload()
            return
        }
        do {
            _ = try await providers.client()
                .rpcAdapted("workspace/unarchiveSession", args: ["request": ["sessionId": session.sessionId]])
            providers.store.archivedSessionIds.remove(session.sessionId)
            await providers.reload()
        } catch {
            providers.reportError("撤销归档失败：\(error.localizedDescription)")
        }
    }

    @MainActor
    func togglePin(_ session: PocketSession) async {
        guard let providers else { return }
        let store = providers.store
        let pinned = store.pinnedSessionIds.contains(session.sessionId)
        if providers.isDemoMode() {
            if pinned {
                store.pinnedSessionIds.removeAll { $0 == session.sessionId }
            } else {
                store.pinnedSessionIds.insert(session.sessionId, at: 0)
            }
            return
        }
        do {
            let endpoint = pinned ? "workspace/unpinSession" : "workspace/pinSession"
            let value = try await providers.client()
                .rpcAdapted(endpoint, args: ["request": ["sessionId": session.sessionId]])
            if let list = value["pinnedSessionIds"] as? [String] {
                store.pinnedSessionIds = list
            } else if pinned {
                store.pinnedSessionIds.removeAll { $0 == session.sessionId }
            } else {
                store.pinnedSessionIds.insert(session.sessionId, at: 0)
            }
        } catch {
            providers.reportError("置顶失败：\(error.localizedDescription)")
        }
    }

    /// 归档会话（从列表移除，桌面端同步隐藏）。
    @MainActor
    func archive(_ session: PocketSession) async {
        guard let providers else { return }
        let store = providers.store
        if providers.isDemoMode() {
            store.sessions.removeAll { $0.sessionId == session.sessionId }
            store.archivedSessionIds.insert(session.sessionId)
            store.pinnedSessionIds.removeAll { $0 == session.sessionId }
            return
        }
        do {
            let value = try await providers.client().rpcAdapted("workspace/archiveSession", args: ["request": [
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
            providers.setLastArchived(session)
            if store.selected?.sessionId == session.sessionId { store.selected = nil }
        } catch {
            providers.reportError("归档失败：\(error.localizedDescription)")
        }
    }

    @MainActor
    func createSession() async {
        guard let providers else { return }
        do {
            var request: [String: Any] = [:]
            if let initialized = try? await providers.client().rpcAdapted("workspace/initializeDefault", args: [:]),
               let workspace = initialized["workspace"] as? [String: Any],
               let workspaceId = workspace["workspaceId"] as? String {
                request["workspaceId"] = workspaceId
            }
            let value = try await providers.client()
                .rpcAdapted("session/create", args: ["request": request])
            guard let id = value["sessionId"] as? String else { throw ConnectionError.invalidPayload }
            let session = PocketSession(sessionId: id, updatedAt: Date().timeIntervalSince1970,
                                        running: false, blank: true)
            await providers.reload()
            if !providers.store.sessions.contains(where: { $0.sessionId == id }) {
                providers.store.sessions.insert(session, at: 0)
            }
            providers.open(session)
        } catch {
            providers.reportError("无法创建会话：\(error.localizedDescription)")
        }
    }
}
