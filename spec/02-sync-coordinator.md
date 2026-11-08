# 02 · Sync Coordinator（单一同步真相源）

## 背景

当前同步逻辑分散在 `ConnectionModel`：`follow`（WS snapshot+events）、`pollLiveFallback`（HTTP 轮询）、
`loadHistory`、`acceptLive`、`mergeMessages/mergeSteps`、看门狗、重连、令牌校验。
这是丢消息、串台、假死、顺序问题反复出现的**结构性原因**。

## 目标

`SessionSyncCoordinator`（actor）成为每个会话的唯一同步源：
- 打开会话：snapshot/历史基线 → 事件增量；
- 断线：指数退避重连 + 25s 看门狗 + 轮询兜底；
- 会话隔离：每个会话一个 coordinator 实例；
- 分页：`loadOlder(hasMore)`；
- 对外只暴露 `AsyncStream<SessionUpdate>`（messages/steps/connection/turn）。

## 参考实现

- `github-references/element-x-ios/.../Services/Timeline/TimelineController/*`
- `github-references/element-x-ios/.../Services/Timeline/TimelineProxy.swift`
- `github-references/stream-chat-swiftui/Sources/StreamChatSwiftUI/ChatChannel/ChatChannelViewModel.swift`

## 测试用例（MockTransport）

### 初始同步
| ID | Given | When | Then |
| --- | --- | --- | --- |
| S01 | snapshot 含 15 条记录 | start | 输出消息/步骤与记录一致 |
| S02 | snapshot 后到达事件 | 收到 | 按 seq 追加，不重复 |
| S03 | snapshot 中重复 seq | start | 去重，只保留一份 |
| S04 | HTTP 历史失败但 WS snapshot 成功 | start | 仍能输出数据，连接状态=connected |

### 增量与顺序
| ID | Given | When | Then |
| --- | --- | --- | --- |
| S10 | 事件 seq 跳号 | 收到 | 触发补拉（loadHistory）且最终补齐 |
| S11 | 事件流中 user/assistant 交错 | 收到 | 输出顺序 = seq 顺序 |
| S12 | 同一事件重复投递 | 收到 | 幂等（一次） |

### 连接状态机
| ID | Given | When | Then |
| --- | --- | --- | --- |
| S20 | 连接成功 | start | state=connected |
| S21 | 25s 无帧且 turn running | 超时 | 主动断开并重连（state 回 connecting） |
| S22 | 重连失败 | 多次 | 指数退避 + attempt 计数递增 |
| S23 | 重连成功 | 恢复 | 补发 snapshot，state=connected |
| S24 | 用户点"重连" | manualReconnect | 立即重连 |

### 会话隔离与生命周期
| ID | Given | When | Then |
| --- | --- | --- | --- |
| S30 | 会话 A 的 coordinator | 收到 B 的事件 | 丢弃且不输出 |
| S31 | 切到 B | A 的任务 | 被取消，A 不再输出到 B |
| S32 | 切回 A | start | A 的历史/状态恢复，不重新拉全量 |

### 分页
| ID | Given | When | Then |
| --- | --- | --- | --- |
| S40 | hasMore=true | loadOlder | 拉更早一页并去重合并 |
| S41 | hasMore=false | loadOlder | 不请求 |

## 预计改动

- 新增 `DSHKit/Sources/DSHKit/Sync/{SessionSyncCoordinator.swift,SessionUpdate.swift,ReconnectPolicy.swift}`
- 新增 `DSHKit/Tests/SyncCoordinatorTests.swift`（含 `MockTransport`）
- 修改 `DSHPocketApp.swift`：`ConnectionModel` 改为持有 coordinators，删除 follow/poll/merge 启发式
- `ConversationState` 保留为 UI store，由 coordinator 驱动

## 实施步骤

1. MockTransport + S01–S41 测试（Red）；
2. actor 骨架 + snapshot/事件循环（Green）；
3. 连接状态机 + 看门狗 + 轮询兜底接入；
4. 切换 A/B 与回退不重拉；
5. 分页；覆盖率 ≥85%，验收。

## 验收结果（2026-11-09，包内）

- ✅ S01–S41（实际 18 条，含 DSHClient 传输实现测试）全绿：`cd DSHKit && swift test`（共 67 tests）
- ✅ DSHKit 行覆盖率 **91.6%**（`DSHKit/scripts/coverage.sh 85` → PASS）
- ⏭ App 接入（`ConnectionModel` 改用 coordinator）在 **02b** 完成；分页游标语义待真实协议确认（当前用同一页兜底 + seq 去重）
- 已知：`SyncConfig.pollInterval` 暂未启用（轮询兜底接入 02b 时使用）

## 验收标准

- [ ] S01–S41 全绿；
- [ ] 现有 E2E（登录/收发/切换/断线重连）全绿；
- [ ] 覆盖率 ≥85%；
- [ ] `ConnectionModel` 中删除了旧的同步启发式代码。
