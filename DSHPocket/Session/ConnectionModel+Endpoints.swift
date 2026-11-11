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
        guard let url = URL(string: address), let host = url.host?.lowercased() else { return .custom }
        if host == "localhost" || host.hasSuffix(".local") { return .lan }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4 {
            let a = parts[0], b = parts[1]
            if a == 127 || a == 10 || (a == 192 && b == 168) || (a == 172 && (16...31).contains(b)) {
                return .lan
            }
        }
        if host.contains("trycloudflare.com") || url.scheme == "https" { return .publicNetwork }
        return .custom
    }

    func loadSavedEndpoints() {
        guard let data = UserDefaults.standard.data(forKey: Self.savedEndpointsKey),
              let list = try? JSONDecoder().decode([SavedEndpoint].self, from: data) else { return }
        savedEndpoints = Self.dedupEndpoints(list)
        seedServerEndpointIfNeeded()
    }

    /// 阿里云开发机。和「家 / 公司」并列，走 3091，不占备案的 80/443。
    func seedServerEndpointIfNeeded() {
        let address = "http://203.0.113.10:3091"
        guard !savedEndpoints.contains(where: { $0.address == address }) else { return }
        savedEndpoints.append(SavedEndpoint(address: address, kind: .custom, lastUsedAt: Date().timeIntervalSince1970, label: "服务器"))
        savedEndpoints = Self.dedupEndpoints(savedEndpoints)
        if let data = try? JSONEncoder().encode(savedEndpoints) {
            UserDefaults.standard.set(data, forKey: Self.savedEndpointsKey)
        }
    }

    /// 去重 + 配额：局域网最多 3 个（可分别命名「公司」「家」），公网 1 个，自定义 1 个。
    /// 公网地址很容易失效，没必要存很多。
    static func dedupEndpoints(_ list: [SavedEndpoint]) -> [SavedEndpoint] {
        var kept: [SavedEndpoint] = []
        var seenAddresses = Set<String>()
        var lanCount = 0
        var publicCount = 0
        var customCount = 0
        for endpoint in list.sorted(by: { $0.lastUsedAt > $1.lastUsedAt }) {
            guard !seenAddresses.contains(endpoint.address) else { continue }
            switch endpoint.kind {
            case .lan:
                guard lanCount < 3 else { continue }
                lanCount += 1
            case .publicNetwork:
                guard publicCount < 1 else { continue }
                publicCount += 1
            case .custom:
                guard customCount < 2 else { continue }
                customCount += 1
            }
            seenAddresses.insert(endpoint.address)
            kept.append(endpoint)
        }
        return kept
    }

    /// 连接成功后记录地址；同一地址只保留一条（供连接页手动选择）。
    func recordEndpoint(_ address: String) {
        guard let url = try? Self.serverURL(from: address) else { return }
        let normalized = url.absoluteString
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
            recordDiagnostic("切换连接：\(endpoint.kind.label) \(endpoint.address)")
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
            recordDiagnostic("Debug 自动连接：\(server)")
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
