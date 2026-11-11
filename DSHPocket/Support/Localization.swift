// 语言与文案

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



// MARK: - 应用内语言（简体中文 / English）

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, zh, en
    var id: String { rawValue }
    func title() -> String {
        switch self {
        case .system: return L10n.t("跟随系统")
        case .zh: return "中文"
        case .en: return "English"
        }
    }
}


@Observable
final class LanguageStore {
    static let shared = LanguageStore()
    private static let key = "dsh-pocket.language"
    var code: AppLanguage {
        didSet {
            UserDefaults.standard.set(code.rawValue, forKey: Self.key)
            NotificationCenter.default.post(name: .appLanguageChanged, object: nil)
        }
    }
    init() {
#if DEBUG
        if let forced = ProcessInfo.processInfo.environment["DSH_LANG"] {
            let mapped: AppLanguage = forced == "en" ? .en : (forced == "zh" ? .zh : (AppLanguage(rawValue: forced) ?? .system))
            code = mapped
            UserDefaults.standard.set(mapped.rawValue, forKey: Self.key)
            return
        }
#endif
        let saved = UserDefaults.standard.string(forKey: Self.key) ?? AppLanguage.system.rawValue
        code = AppLanguage(rawValue: saved) ?? .system
    }
    var isEnglish: Bool {
        switch code {
        case .en: return true
        case .zh: return false
        case .system:
            let lang = Locale.preferredLanguages.first ?? "zh"
            return !lang.lowercased().hasPrefix("zh")
        }
    }
}


/// 轻量文案表：key 为中文原文，按语言返回对应文案；未收录的文案保持中文。
enum L10n {
    static func t(_ zh: String) -> String {
        LanguageStore.shared.isEnglish ? (en[zh] ?? zh) : zh
    }
    static func tf(_ format: String, _ args: CVarArg...) -> String {
        String(format: t(format), arguments: args)
    }
    static let en: [String: String] = [
        "连接你的 DSH": "Connect to your DSH",
        "输入电脑地址和访问密码": "Enter your computer address and access PIN",
        "使用说明": "How to use",
        "已保存的连接": "Saved connections",
        "点按切换": "Tap to switch",
        "局域网最多保留 3 个（可命名为「公司」「家」），公网保留最近 1 个；公网地址变化后重新扫码更新。": "Up to 3 LAN addresses (name them Office/Home) and the latest 1 public address. Rescan if the public address changes.",
        "连接": "Connect",
        "体验演示模式": "Try demo mode",
        "演示模式使用内置示例数据，不会连接或发送任何内容。": "Demo mode uses sample data. It never connects or sends anything.",
        "会话": "Sessions",
        "演示模式": "Demo mode",
        "示例数据，未连接电脑": "Sample data · not connected",
        "退出": "Exit",
        "设置": "Settings",
        "语言": "Language",
        "跟随系统": "Follow system",
        "中文": "简体中文",
        "完成提醒": "Completion alerts",
        "完成提醒：开启": "Completion alerts: on",
        "完成提醒：关闭": "Completion alerts: off",
        "版本": "Version",
        "开始对话": "Start a conversation",
        "发送第一条消息。": "Send your first message.",
        "加载更早消息…": "Loading earlier messages…",
        "实时连接": "Live",
        "发送消息": "Message",
        "你": "You",
        "停止": "Stop",
        "深度求索中": "Thinking",
        "本轮运行失败": "This turn failed",
        "当前请求的额度已用尽": "Insufficient balance for this request",
        "切换模型失败：上下文压缩没有完成，额度不足。": "Could not switch models: context compaction failed because the balance is insufficient.",
        "已连接": "Connected",
        "连接中…": "Connecting…",
        "重连中…": "Reconnecting…",
        "已断开": "Disconnected",
        "重试": "Retry",
        "断开连接": "Disconnect",
        "退出演示模式": "Exit demo mode",
        "开启完成提醒": "Enable completion alerts",
        "关闭完成提醒": "Disable completion alerts",
        "发送中…": "Sending…",
        "已发出，等待处理": "Sent · waiting",
        "已引导，正在继续": "Steering · continuing",
        "发送失败": "Send failed",
        "等待网络，恢复后自动发送": "Waiting for network · will send automatically",
        "后台任务": "Background jobs",
        "没有后台任务": "No background jobs",
        "这个会话还没有启动后台任务。": "This session has not started any background job.",
        "正在运行": "Running",
        "正在停止": "Stopping",
        "已完成": "Completed",
        "已停止": "Stopped",
        "失败": "Failed",
        "开始于": "Started",
        "重新发送": "Resend",
        "复制整条消息": "Copy message",
        "引用这条消息": "Quote message",
        "取消引用": "Cancel quote",
        "引用": "Quote",
        "显示": "Show",
        "隐藏": "Hide",
        "复制": "Copy",
        "随机更换": "Regenerate",
        "自定义": "Custom",
        "密码不正确或已变更，请重新输入访问密码。": "PIN is incorrect or changed. Please enter it again.",
        "登录已过期或访问密码已变更，请重新输入密码连接。": "Session expired or PIN changed. Please reconnect.",
        "这条消息服务端没有收到，点消息下方「重新发送」可重试。": "The server did not receive this message. Tap Resend below.",
        "过程": "Steps",
        "步": "steps",
        "待发送": "Pending",
        "已复制": "Copied",
        "访问密码": "Access PIN",
        "删除连接": "Delete connection",
        "粘贴": "Paste",
        "断开与电脑的连接？": "Disconnect from your computer?",
        "断开后需要重新扫码配对（或输入访问密码）才能再次连接。": "After disconnecting you must scan the pairing QR again (or enter the access PIN) to reconnect.",
        "登录已过期（DSH 可能重启过），请重新扫码配对或输入访问密码。": "Your session expired (DSH may have restarted). Scan the pairing QR again or enter the access PIN.",
        "推荐": "Recommended",
        "扫码连接电脑": "Scan to connect",
        "扫一扫，连接电脑": "Scan QR to connect",
        "在电脑上打开 DSH → 设置 →「手机访问（iOS）」": "On your Mac, open DSH → Settings → Phone access (iOS)",
        "用本 App 扫描设置页上的二维码": "Scan the QR code from that page with this app",
        "自动连接，无需输入密码": "Connects automatically, no password needed",
        "或手动连接（输入地址与密码）": "Or connect manually (address + password)",
        "方式一（推荐）：Tailscale": "Option 1 (recommended): Tailscale",
        "电脑装 Tailscale + dsh-pocket-ios 连接器，手机装 Tailscale 和本 App；扫码即连，地址固定": "Install Tailscale + the dsh-pocket-ios connector on your Mac, Tailscale and this app on your phone; scan to connect, fixed address",
        "方式二：dsh-pocket": "Option 2: dsh-pocket",
        "电脑装 dsh-pocket 插件（可选再加 dsh-pocket-ios 连接器）；扫它的局域网/公网二维码后输入访问密码": "Install the dsh-pocket plugin on your Mac (optionally add the dsh-pocket-ios connector); scan its LAN/public QR and enter the access PIN",
        "按你选的路线装好对应插件（方式一：dsh-pocket-ios；方式二：dsh-pocket）": "Install the plugin for the option you picked (Option 1: dsh-pocket-ios; Option 2: dsh-pocket)",
        "打开电脑 DSH → 设置 → 手机访问": "Open DSH on your Mac → Settings → Phone access",
        "扫码：方式一自动连接；方式二输入访问密码": "Scan: Option 1 connects automatically; Option 2 asks for the access PIN",
        "已填入地址，请输入电脑上显示的访问密码（方式二）": "Address filled in. Enter the access PIN shown on your Mac (Option 2).",
        "准备（二选一）": "Before you start (pick one)",
        "Tailscale（推荐）": "Tailscale (recommended)",
        "Mac 和 iPhone 都安装并登录同一账号：地址固定、连接更稳定，换 Wi-Fi/切 4G 不用重新扫码": "Install Tailscale on both your Mac and iPhone with the same account: fixed address, more stable, no rescanning when switching networks",
        "dsh-pocket 插件": "dsh-pocket plugin",
        "在 Mac 的 DSH 插件市场安装 dsh-pocket，提供局域网/公网二维码；适合同一 Wi-Fi 或使用代理网络的场景": "Install dsh-pocket from the DSH plugin market: gives LAN/public QR codes; good for same-Wi-Fi or proxy setups",
        "然后": "Then",
        "在 Mac 上安装 dsh-pocket-ios 插件（提供「手机访问（iOS）」设置页）": "Install the dsh-pocket-ios plugin on your Mac (adds the Phone access (iOS) settings page)",
        "打开 DSH → 设置 →「手机访问（iOS）」": "Open DSH → Settings → Phone access (iOS)",
        "用本 App 扫描该页面上的二维码": "Scan the QR code on that page with this app",
        "访问密码（扫码连接可跳过）": "Access PIN (optional when scanning)",

        "删除连接？": "Delete this connection?",
        "删除": "Delete",
        "取消": "Cancel",
        "局域网": "LAN",
        "公网": "Public",
        "未连接": "Not connected",
        "正在连接": "Connecting",
        "正在重连": "Reconnecting",
        "重连中（第 %d 次）": "Reconnecting (%d)",
        "重连": "Retry",
        "新建会话": "New session",
        "切换连接": "Switch connection",
        "还没有会话": "No sessions yet",
        "创建会话后即可开始对话。": "Create a session to start chatting.",
        "完成": "Done",
        "演示模式 · 示例数据，未连接电脑": "Demo · sample data, not connected",
        "会同步到电脑端的会话标题。": "Syncs the title to the session on your computer.",
        "会话列表": "Session list",
        "会话名称": "Session name",
        "会话已归档": "Session archived",
        "保存": "Save",
        "保存到相册": "Save to Photos",
        "关闭": "Close",
        "其他会话": "Other sessions",
        "取消置顶": "Unpin",
        "命名连接地址": "Name this connection",
        "图片加载失败": "Image failed to load",
        "复制会话地址": "Copy session address",
        "复制会话日志路径": "Copy session log path",
        "复制诊断信息": "Copy diagnostics",
        "对话记录": "Chat history",
        "已完成，等待你的回复": "Done, waiting for your reply",
        "已置顶": "Pinned",
        "归档": "Archive",
        "打开 DSH Pocket iOS 使用说明": "Open the DSH Pocket iOS guide",
        "扫描二维码": "Scan QR code",
        "按工作区分组": "Group by workspace",
        "按时间线": "Timeline",
        "提交回答": "Submit answer",
        "撤销": "Undo",
        "显示方式": "Layout",
        "更多": "More",
        "来自电脑端 DSH": "From DSH on your computer",
        "正在加载模型…": "Loading models…",
        "正在运行": "Running",
        "清除": "Clear",
        "滚到底部": "Scroll to bottom",
        "给这个地址起一个有辨识度的名字，例如「公司」或「家」。": "Give this address a recognizable name, e.g. Office or Home.",
        "置顶": "Pin",
        "选择模型": "Model",
        "重命名": "Rename",
        "重命名会话": "Rename session",
        "重新扫码连接": "Scan again to reconnect",
        "需要你确认": "Needs your confirmation",
        "默认工作区": "Default workspace",
    ]
}
