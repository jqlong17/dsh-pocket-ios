# 03 · 消息生命周期（状态机 / 对账 / 排序 / steer）

## 背景

我们已修过：pending 按文本去重误删（消息不显示）、requestId 不一致（永远"发送中"）、
排队消息顺序、steer/queue 混淆。根因是**没有显式消息状态机与稳定身份**。

## 目标

- `MessageSendState`：`sending → accepted(steer/queue) → committed | failed`；
- 身份：`rpcId`（服务端回填 `source.rpcId`），禁止文本去重；
- 发件箱 `Outbox`：持久化、TTL、重启恢复；
- 排序：服务端 seq 为唯一顺序；pending 固定末尾；排队消息按 turn 边界后置；
- 发送模式：运行中 steer（引导），空闲 queue。

## 参考实现

- `github-references/element-x-ios/.../TimelineItemIdentifier.swift`（uniqueID + eventID/transactionID）
- `github-references/stream-chat-swiftui/.../MessageListHelperViews.swift`（LocalMessageState）
- `github-references/stream-chat-swiftui/.../ChatChannelViewModel.swift`（resendMessage）

## 测试用例

### 状态机
| ID | Given | When | Then |
| --- | --- | --- | --- |
| M01 | 点击发送 | 开始 | state=sending，列表中末尾出现 pending |
| M02 | 服务端 ACK | 收到 | state=accepted（steer 标记来自 promptMode） |
| M03 | 收到 user/message(rpcId 匹配) | 合并 | pending 移除，正式消息就位，state 清除 |
| M04 | 发送失败 | 错误 | state=failed，气泡保留，可重发 |
| M05 | 点击重发 | retry | 用发件箱文本重新发送，旧 pending 移除 |
| M06 | 取消发送 | cancel | pending/发件箱移除，文本回填（草稿为空时） |

### 对账（禁止文本去重）
| ID | Given | When | Then |
| --- | --- | --- | --- |
| M10 | 历史里已有相同文本的旧消息 | 发送同文本新消息 | 新 pending **不**被误删 |
| M11 | 服务端不回 rpcId | 收到新用户消息 | 仅"发送后最后一条同文本"可确认 |
| M12 | 重复回放同一 user/message | 合并 | 幂等，不重复 |

### 发件箱
| ID | Given | When | Then |
| --- | --- | --- | --- |
| M20 | 发送后重启 App | 打开会话 | 未确认消息恢复为 pending |
| M21 | 条目超过 10 分钟 | 加载 | 清理，不再显示"发送中" |
| M22 | 已确认 | 合并历史 | 条目移除 |
| M23 | 失败条目 | 合并历史 | 保留（可重发） |

### 排序
| ID | Given | When | Then |
| --- | --- | --- | --- |
| M30 | 普通消息 | 排序 | 按 seq 升序 |
| M31 | 生成中排队消息（seq 落在 turn 区间） | 排序 | 排到该 turn 结束之后 |
| M32 | 同 turn 内多条排队消息 | 排序 | 按原始 seq 保持发送顺序 |
| M33 | pending | 排序 | 永远在末尾 |

### 发送模式
| ID | Given | When | Then |
| --- | --- | --- | --- |
| M40 | turn running | 发送 | 使用 `mode=steer` |
| M41 | 空闲 | 发送 | 使用 `mode=queue`（等价普通一轮） |
| M42 | prompt 请求 | 编码 | `requestId` == 发件箱/ pending 的 rpcId |

## 预计改动

- 新增 `DSHKit/Sources/DSHKit/Store/{MessageState.swift,Outbox.swift,MessageOrdering.swift}`
- 新增 `DSHKit/Tests/MessageLifecycleTests.swift`
- 修改 `DSHPocketApp.swift`：删除 `ackedSendRpcIds/failedSendRpcIds/turnStarts/turnEnds` 等散落状态，
  改用 store API；`ConversationState` 仅保留视图所需数据

## 实施步骤

1. M01–M42 测试（Red）；
2. 状态机 + Outbox 实现（Green）；
3. 排序函数（纯函数，fixture 驱动）；
4. 接入发送/接收路径；删除旧启发式；
5. 覆盖率 ≥85%，验收。

## 验收结果（2026-11-09，包内）

- ✅ M01–M42 对应用例（实际 25 条）全绿；DSHKit 总测试 92 条
- ✅ Store 模块行覆盖率：MessageLifecycle 93.0% / Ordering 97.6% / Outbox 100% / Reconciler 100%
- ✅ 发送模式（steer/queue）、rpcId 对账、发件箱 TTL、排序（turn 区间/二级 seq/pending 末尾）全部有单测锁定
- ⏭ App 接入随 02b（App 仍使用内联逻辑，接入时替换为 Store API）

## 验收标准

- [ ] M01–M42 全绿；
- [ ] 覆盖率 ≥85%；
- [ ] 历史消息不再出现"发送中"；重发可用。
