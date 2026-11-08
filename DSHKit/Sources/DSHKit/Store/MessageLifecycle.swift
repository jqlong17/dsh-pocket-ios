import Foundation

/// 发送模式（模块 03）：生成中 steer，空闲 queue。
public enum SendMode: String, Codable, Equatable, Sendable {
    case queue
    case steer
}

/// 单条消息的发送状态机：sending → accepted → committed/failed。
public enum MessageSendState: Equatable, Sendable {
    case sending
    case accepted(SendMode)
    case committed
    case failed
}

/// 发送状态机（纯逻辑，便于单测；App 侧按 rpcId 驱动）。
public struct MessageLifecycle {
    private var states: [String: MessageSendState] = [:]
    private var modes: [String: SendMode] = [:]

    public init() {}

    @discardableResult
    public mutating func begin(rpcId: String, mode: SendMode) -> MessageSendState {
        states[rpcId] = .sending
        modes[rpcId] = mode
        return .sending
    }

    @discardableResult
    public mutating func acknowledge(rpcId: String) -> MessageSendState {
        guard let mode = modes[rpcId] ?? states[rpcId].flatMap({ state -> SendMode? in
            if case .accepted(let mode) = state { return mode }
            return nil
        }) else { return .failed }
        states[rpcId] = .accepted(mode)
        return .accepted(mode)
    }

    @discardableResult
    public mutating func fail(rpcId: String) -> MessageSendState {
        states[rpcId] = .failed
        return .failed
    }

    @discardableResult
    public mutating func commit(rpcId: String) -> MessageSendState {
        states[rpcId] = .committed
        return .committed
    }

    public func state(for rpcId: String) -> MessageSendState? { states[rpcId] }
    public func mode(for rpcId: String) -> SendMode? { modes[rpcId] }
    public func acceptedRpcIds() -> Set<String> {
        Set(states.compactMap { key, value in
            if case .accepted = value { return key }
            return nil
        })
    }
    public func failedRpcIds() -> Set<String> {
        Set(states.compactMap { key, value in
            if case .failed = value { return key }
            return nil
        })
    }
}

public enum SendModeDecider {
    public static func mode(isTurnRunning: Bool) -> SendMode {
        isTurnRunning ? .steer : .queue
    }
}
