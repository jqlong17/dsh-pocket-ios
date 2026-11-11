// 已保存的服务器地址

import SwiftUI
import Security
import Textual
import DSHKit
import VisionKit
import AVFoundation
import Observation
import PhotosUI
import UIKit
import Photos
import os
import AudioToolbox
import ImageIO
import UserNotifications

extension ConnectionModel {

    static func endpointKind(of address: String) -> SavedEndpoint.Kind {
        SavedEndpoint.Kind(DSHEndpointPolicy.kind(of: address))
    }

    func loadSavedEndpoints() {
        guard let data = UserDefaults.standard.data(forKey: Self.savedEndpointsKey),
              let list = try? JSONDecoder().decode([SavedEndpoint].self, from: data) else { return }
        savedEndpoints = Self.dedupEndpoints(list)
        seedServerEndpointIfNeeded()
    }

    /// 仅 DEBUG 下播种开发机地址，且地址来自启动环境变量（DSH_DEV_SERVER），
    /// 代码里不留任何公网地址，正式包更不会写入 UserDefaults。
    /// 用户已经手工保存的端点一律保留。
    func seedServerEndpointIfNeeded() {
#if DEBUG
        let address = (ProcessInfo.processInfo.environment["DSH_DEV_SERVER"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }
        let existing = savedEndpoints.map(\.address)
        guard DSHEndpointPolicy.shouldAutoSeedDevelopmentEndpoint(
            isDebugBuild: true,
            existingAddresses: existing,
            developmentAddress: address
        ) else { return }
        savedEndpoints.append(SavedEndpoint(address: address, kind: .custom, lastUsedAt: Date().timeIntervalSince1970, label: "服务器"))
        savedEndpoints = Self.dedupEndpoints(savedEndpoints)
        if let data = try? JSONEncoder().encode(savedEndpoints) {
            UserDefaults.standard.set(data, forKey: Self.savedEndpointsKey)
        }
#endif
    }

    /// 去重 + 配额交给 DSHKit；这里只做模型映射。
    static func dedupEndpoints(_ list: [SavedEndpoint]) -> [SavedEndpoint] {
        let records = list.map {
            DSHSavedEndpointRecord(address: $0.address, kind: $0.kind.policyKind, lastUsedAt: $0.lastUsedAt, label: $0.label)
        }
        return DSHEndpointPolicy.dedup(records).map {
            SavedEndpoint(address: $0.address, kind: SavedEndpoint.Kind($0.kind), lastUsedAt: $0.lastUsedAt, label: $0.label)
        }
    }

    /// 连接成功后记录地址；同一地址只保留一条（供连接页手动选择）。
    func recordEndpoint(_ address: String) {
        guard let url = try? Self.serverURL(from: address) else { return }
        // 存的是去参数后的地址：配对 token 只用于当次登录，不写进地址列表。
        let normalized = DSHURL.baseAddress(url)
        let existingLabel = savedEndpoints.first(where: { $0.address == normalized })?.label
        var list = savedEndpoints.filter { $0.address != normalized }
        list.append(SavedEndpoint(address: normalized,
                                  kind: Self.endpointKind(of: normalized),
                                  lastUsedAt: Date().timeIntervalSince1970,
                                  label: existingLabel))
        savedEndpoints = Self.dedupEndpoints(list)
        if let data = try? JSONEncoder().encode(savedEndpoints) {
            UserDefaults.standard.set(data, forKey: Self.savedEndpointsKey)
        }
    }

    /// 用 session/list 的最新 running 校验一次（只在没有实时 turn 事件时生效）。
    @MainActor
    func refreshRunningState(for sessionId: String) async {
        guard activeConversation?.sessionId == sessionId,
              activeConversation?.liveTurnEventsSeen == false,
              let fresh = try? await fetchSessions(),
              let latest = fresh.first(where: { $0.sessionId == sessionId }) else { return }
        if !latest.running {
            isTurnRunning = false
            turnStartedAt = nil
            recordDiagnostic("运行状态校验：会话已结束")
        } else {
            recordDiagnostic("运行状态校验：仍在运行")
        }
    }

    /// 把回复切成有序片段：文本段与图片段交替，图片按 Markdown 中的原位置渲染。
    func markdownSegments(_ markdown: String) -> [MarkdownSegment] {
        guard markdown.contains("![") else { return [.text(markdown)] }
        var segments: [MarkdownSegment] = []
        var buffer: [String] = []
        let regex = try? NSRegularExpression(pattern: #"^!\[([^\]]*)\]\(([^)\s]+)\)$"#)

        func flushText() {
            let joined = buffer.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.text(joined))
            }
            buffer.removeAll()
        }

        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let regex,
               let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let captionRange = Range(match.range(at: 1), in: trimmed),
               let destinationRange = Range(match.range(at: 2), in: trimmed) {
                let caption = String(trimmed[captionRange])
                let destination = String(trimmed[destinationRange])
                if let url = markdownImageURL(for: destination) {
                    flushText()
                    segments.append(.image(url, caption: caption.isEmpty ? nil : caption))
                    continue
                }
            }
            buffer.append(line)
        }
        flushText()
        return segments.isEmpty ? [.text(markdown)] : segments
    }

    func markdownImageURL(for destination: String) -> URL? {
        if let url = URL(string: destination),
           let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            return url
        }
        guard let base = try? Self.serverURL(from: serverAddress) else { return nil }
        var raw = destination.removingPercentEncoding ?? destination
        if raw.hasPrefix("file://") { raw = String(raw.dropFirst("file://".count)) }
        else if raw.hasPrefix("file:") { raw = String(raw.dropFirst("file:".count)) }
        guard !raw.isEmpty else { return nil }
        let absolute: String
        if raw.hasPrefix("/") {
            absolute = raw
        } else if let cwd = selectedSession?.cwd, cwd.hasPrefix("/") {
            absolute = URL(fileURLWithPath: cwd).appendingPathComponent(raw).standardized.path
        } else {
            return nil
        }
        var components = URLComponents(url: base.appending(path: "api/file"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "path", value: absolute)]
        return components?.url
    }

    /// 会话列表的 updatedAt 可能是毫秒或秒，统一成 Date。
    static func dateFromSessionUpdatedAt(_ value: TimeInterval) -> Date {
        let seconds = value > 10_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }

    /// 给已保存地址设置/清除自定义标签（如「公司」「家」）。
    /// 删除一条已保存的连接（只删记录，不影响当前正在使用的地址）。
    @MainActor
    func removeEndpoint(_ address: String) {
        savedEndpoints.removeAll { $0.address == address }
        if let data = try? JSONEncoder().encode(savedEndpoints) {
            UserDefaults.standard.set(data, forKey: Self.savedEndpointsKey)
        }
    }

    func renameEndpoint(_ address: String, label: String?) {
        guard let index = savedEndpoints.firstIndex(where: { $0.address == address }) else { return }
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        savedEndpoints[index].label = (trimmed?.isEmpty == false) ? trimmed : nil
        if let data = try? JSONEncoder().encode(savedEndpoints) {
            UserDefaults.standard.set(data, forKey: Self.savedEndpointsKey)
        }
    }

    /// 手动切换到某个已保存地址（失败时回滚，保持原连接）。
    @MainActor
    func switchToEndpoint(_ endpoint: SavedEndpoint) async {
        guard !isDemoMode else { return }
        let previous = serverAddress
        serverAddress = endpoint.address
        errorMessage = nil
        do {
            sessions = try await fetchSessions()
            isConnected = true
            recordEndpoint(endpoint.address)
            recordDiagnostic("切换连接：\(endpoint.kind.label) \(DSHURL.redactedAddress(endpoint.address))")
        } catch {
            serverAddress = previous
            applyConnectError(error)
            if isConnected { recordDiagnostic("切换连接失败，已回滚：\(error.localizedDescription)") }
        }
    }

    @MainActor
    func restoreConnection() async {
        if isDemoMode { return }
#if DEBUG
        if DebugLaunch.showConnect { return }
        if DebugLaunch.demoMode { startDemoMode(); return }
        if let server = DebugLaunch.server {
            serverAddress = server
            if let pin = DebugLaunch.pin { self.pin = pin }
            recordDiagnostic("Debug 自动连接：\(DSHURL.redactedAddress(server))")
            await connect()
            return
        }
#endif
        guard UserDefaults.standard.string(forKey: Self.savedServerAddressKey) != nil,
              (try? Self.serverURL(from: serverAddress)) != nil else { return }
        do {
            sessions = try await fetchSessions()
            isConnected = true
            errorMessage = nil
        } catch {
            isConnected = false
            applyConnectError(error)
        }
    }

    @MainActor
    func disconnect() {
        if isDemoMode { exitDemoMode(); return }
        conversationToken = UUID()
        turnStarts.removeAll()
        turnEnds.removeAll()
        liveTask?.cancel()
        fallbackTask?.cancel()
        liveTask = nil
        for conversation in conversations.values {
            conversation.liveTask?.cancel()
            conversation.fallbackTask?.cancel()
            conversation.coordinatorTask?.cancel()
            if let coordinator = conversation.coordinator { Task { await coordinator.stop() } }
        }
        conversations.removeAll()
        activeConversation = nil
        selectedSession = nil
        sessions = []
        archivedSessionIds = []
        liveConnection = .idle
        isConnected = false
    }
}
