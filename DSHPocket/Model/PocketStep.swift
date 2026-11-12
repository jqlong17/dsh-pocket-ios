// PocketStep

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


/// 一轮里的一个工具调用步骤（对应 Mac 端"执行了命令 / 查看了图片"那一行）。
struct PocketStep: Identifiable {
    let id: String
    let sequence: Int
    let turn: Int
    let number: Int
    let name: String
    let detail: String
    var resultText = ""
    var isError = false
    var finished = false
    var images: [PocketImageRef] = []
    /// 过程正文默认不留在内存里，展开后再拉取。
    var detailsLoaded = false

    var label: String {
        switch name {
        case "bash": L10n.t("执行了命令")
        case "read": L10n.t("读取了文件")
        case "read_image": L10n.t("查看了图片")
        case "edit": L10n.t("编辑了文件")
        case "write": L10n.t("写入了文件")
        case "web_search": L10n.t("搜索了网页")
        case "web_fetch": L10n.t("抓取了网页")
        case "job_output": L10n.t("读取了任务输出")
        case "todo_write": L10n.t("更新了待办")
        case "ask_user_question": L10n.t("向你确认问题")
        default: name
        }
    }

    /// 正在执行时的进行时文案（Mac 端那种"正在运行命令…"的实时感）。
    var runningLabel: String {
        switch name {
        case "bash", "exec_command", "pwsh", "write_stdin", "terminal_read", "terminal_open": L10n.t("正在运行命令…")
        case "read": L10n.t("正在读取文件…")
        case "read_image": L10n.t("正在查看图片…")
        case "grep", "glob", "search": L10n.t("正在搜索…")
        case "write": L10n.t("正在写入文件…")
        case "edit", "apply_patch": L10n.t("正在编辑文件…")
        case "web_search": L10n.t("正在搜索网页…")
        case "web_fetch": L10n.t("正在打开网页…")
        case "job_output": L10n.t("正在读取任务输出…")
        case "todo_write": L10n.t("正在更新待办…")
        case "ask_user_question": L10n.t("正在等待你的选择…")
        case "present": L10n.t("正在展示…")
        case "subagent", "subagent_fork": L10n.t("正在运行子任务…")
        default: L10n.tf("正在执行 %@…", name)
        }
    }

    var icon: String {
        switch name {
        case "bash": "terminal"
        case "read", "read_image": "doc.text.magnifyingglass"
        case "edit", "write": "square.and.pencil"
        case "web_search", "web_fetch": "globe"
        case "todo_write": "checklist"
        case "ask_user_question": "questionmark.bubble"
        default: "gearshape"
        }
    }
}
