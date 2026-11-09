# 06 · 后台完成推送（APNs）

> 状态：已实现（本地通知回复 + APNs 推送链路，待 Key 配置后真机验证） · 目标版本：1.1.0 · 关联：完成提醒（红点/铃声/本地通知）

## 1. 背景与目标

当前"完成提醒"依赖 App 在前台每 10 秒轮询 `session/list`：App 进入后台后很快被系统挂起，轮询停止，因此**后台不会收到提醒**，只有回到前台时才补检测。

目标：**会话在后台跑完（running → idle）时，手机锁屏/App 在后台也能收到系统通知**，点击通知直接打开对应会话。

非目标：
- 不做消息内容推送（隐私：通知只显示会话标题/通用文案）；
- 不做远程控制会话（发消息、停止生成仍只在 App 内）；
- 不替代现有前台红点/本地提醒逻辑。

## 2. 总体方案

```
iPhone App                      Mac（DSH + dsh-pocket-ios 插件）              APNs
────────                        ─────────────────────────────────            ────
启动/登录成功
  → 注册 deviceToken  ────────▶  push.register(token, env, topics)
                                  存 ~/.dsh/dsh-pocket-ios/push.json
                                  （chmod 600，多设备 token 列表）
                                  轮询/订阅 session 状态
                                  running → idle 且非"正在查看"?
                                     → 构造 payload + JWT
                                     → HTTP/2 POST /3/device/<token> ─────▶ 推送
                                                                             │
锁屏/后台收到通知 ◀───────────────────────────────────────────────────────────┘
点击 → 打开对应 sessionId
```

关键决策：
- **在电脑侧检测完成**（插件本来就在 DSH 进程内，能看到所有会话状态），而不是依赖手机后台执行；
- **APNs 直连**：插件用 `.p8` + JWT（ES256）调用 APNs HTTP/2，不依赖第三方推送服务；
- **通知内容脱敏**：仅 `对话已完成` + 会话标题（标题本身可关，默认显示），不带消息正文；
- **单用户多设备**：一个 tailnet/账号可注册多台 iPhone/iPad，逐个 token 推送。

## 3. 详细设计

### 3.1 App 侧

1. 开启 Push Notifications capability（entitlement `aps-environment`: development/production），App Store 版本用 production；
2. 启动后若用户已允许通知（现有权限申请流程），调用 `UIApplication.shared.registerForRemoteNotifications()`；
3. `didRegisterForRemoteNotificationsWithDeviceToken` → 十六进制 token → 调插件 RPC `push.register`：
   ```json
   { "token": "<hex>", "environment": "sandbox|production", "bundleId": "com.ruska.dsh-pocket-ios", "deviceName": "iPhone 17 Pro" }
   ```
4. 通知开关（现有「完成提醒」铃铛）关闭时调用 `push.unregister`；重新打开时重新注册；
5. 前台收到推送（`willPresent`）→ 只更新红点/不弹 banner（已有前台轮询会处理），或返回 `[.list, .sound]` 视产品取舍；
6. 点击通知 → 用 payload `sessionId` 打开会话；若会话已归档/不存在，落到会话列表并提示；
7. Token 变化（重装/系统迁移）→ 重新 `push.register`，服务端去重。

### 3.2 插件侧（dsh-pocket-ios，host）

1. 新增 RPC 端点（复用现有 `/dsh-pocket-ios` 通道）：
   - `push.register`：写入 token 列表（按 token 去重、更新时间、environment）；
   - `push.unregister`：删除 token；
   - `push.status`：调试用（token 数量、最近一次推送结果）；
2. **完成检测**：MVP 用服务端轮询 `session/list`（每 5 秒）维护 `sessionId → running` 状态机（与 App 的 `SessionCompletionTracker` 同逻辑）；后续可改为订阅 DSH 事件总线；
3. 排除规则：
   - 会话在最近 N 秒内由手机端正在查看（App 上报 `foregroundSession`，可选）→ 不推送；
   - 同一 `(sessionId, turnEndSeq)` 只推一次（幂等键）；
   - 会话被手动停止（aborted）不推「已完成」，但可按需推「已停止」。
4. **APNs 发送**：
   - 配置：`~/.dsh/dsh-pocket-ios/apns.json`（keyId、teamId、`.p8` 路径；不要入库/提交 Git）；
   - JWT 缓存 50 分钟，ES256 签名（Node `crypto`，无需第三方库）；
   - 请求：`POST https://api.push.apple.com/3/device/<token>`（sandbox 用 `api.sandbox.push.apple.com`），HTTP/2；
   - headers：`apns-topic: com.ruska.dsh-pocket-ios`、`apns-push-type: alert`、`apns-priority: 10`、`authorization: bearer <jwt>`；
   - payload：
     ```json
     { "aps": { "alert": { "title": "对话已完成", "body": "「项目名」等待你的回复" }, "sound": "default", "badge": 1 },
       "sessionId": "session-...", "kind": "turn-completed" }
     ```
   - 响应处理：`200` 成功；`410/BadDeviceToken` 删除 token；`429/5xx` 指数退避重试（最多 3 次）；
5. 推送日志：`~/.dsh/dsh-pocket-ios/push.log`（只记 sessionId、token 尾号、结果，不记正文）。

### 3.3 App 与插件的兼容

- 老 App / 老插件：无 `push.*` 端点时，App 注册失败静默降级为现在的"前台提醒"；
- 老 App 协议里扫二维码已支持 `?pin=`（本次已实现），推送不影响该流程；
- 插件版本升级保持 0.x 兼容，RPC 增加端点属于向后兼容。

## 4. 配置与安全

- `.p8` 由开发者在 Apple Developer 后台创建（Keys → APNs），权限仅存于本机 `~/.dsh/dsh-pocket-ios/`（chmod 600）；
- token 文件同样权限 600；不上传任何第三方服务；
- 通知内容不含消息正文、不含 PIN、不含地址；
- 用户关闭「完成提醒」或撤销通知权限 → 服务端删除/停用 token（下次 App 启动时同步）。

## 5. 测试计划

单元/契约：
- `push.register/unregister` 幂等、去重、权限校验（reject 非 loopback）；
- payload 构造、JWT 生成（固定 key 的签名快照）；
- `410` 清理 token、`429` 退避；
- session 状态机：首次观察不推送、running→idle 推一次、再次 running 后完成再推。

真机 E2E：
1. Mac 配置 APNs key，DSH 重启插件；
2. 手机装开发版（sandbox），允许通知，确认 `push.status` 有 1 个 token；
3. 在会话里发起一个长任务，锁屏等待完成 → 收到通知；
4. 点击通知 → 打开对应会话；
5. 前台时完成 → 不重复弹 banner（红点正常）；
6. 关掉「完成提醒」→ 不再收到；重新打开 → 恢复。

## 6. 验收标准

- [ ] App 在后台/锁屏时，会话 running→idle 5 秒内收到通知（正常网络）；
- [ ] 通知点击能直达会话；
- [ ] 同一完成事件不重复推送；
- [ ] token 失效（卸载重装）后自动清理，不产生持续 410；
- [ ] 通知内容不含正文/PIN/地址；
- [ ] 关闭开关后完全停止推送。

## 7. 风险与后续

- APNs 需要开发者账号的 Push 能力与 `.p8` 配置，属于一次性设置；
- 服务端轮询 `session/list` 成本低（单机），后续可改为事件订阅；
- 若未来支持多用户/共享设备，需要 token→用户映射与权限模型（暂不做）；
- 可选扩展：Live Activity（锁屏实时显示"正在运行/已完成"）复用车端推送通道。

## 8. 排期建议

1. 插件 host：token 存储 + APNs 发送 + session 状态机（0.5–1 天）
2. App：注册/注销、深链、前台策略（0.5 天）
3. 真机联调 + 边界（>0.5 天）
4. 文档/CHANGELOG（0.5 天）
