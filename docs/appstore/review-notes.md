# App Store 审核文案库

每次提交审核的 `App Review Information → Notes` 都存一份在这里，便于下一版照着写。
拉取方式见文末。

---

## 通用结构（从 1.0.10 提炼）

历史文案都是这六段，顺序固定。**缺哪段都会被审核员追问**：

```markdown
## What this build (X.Y.Z) changes
本次改动。只讲「用户可感知的变化」，一条一句，动词开头。
不要写内部重构、不要写代码细节。

（一小段产品定位，每次都要写——审核员不会记得上一版）
DSH Pocket is a client for DeepSeek Harness (DSH), an open-source AI coding
agent that the user runs on their own computer. The app has no account system
and runs no server: it connects directly to the user's own Mac over the local
network or a tunnel they create, using an access PIN they set.

## How reviewers can test everything without a computer
**这段是全篇最重要的**。没有它，「App 需要外部服务才能用」会被判 2.1 拒绝。
必须写清：点哪个按钮 → 能看到什么 → 为什么不需要网络。

## Full functionality (optional)
完整功能怎么开：用户自己的电脑 + 插件 + 扫码。写清楚「可选」。

## Privacy
逐条对应用到的权限：相机（扫码）、相册（发图）、通知、本地网络。
每条都要说明「只发到用户自己的电脑，不发给我们」。

## Metadata / trademark note（仅在涉及 Apple 商标时写）
Guideline 5.2.5。元数据里不能出现 iPhone/iOS 等 Apple 产品名。
```

**关键判据**（写之前自问）：

1. **审核员能只靠这段文字把 App 跑起来吗？** 不能 → 补 `How reviewers can test`
2. **有没有「需要自建服务器」却没解释？** 有 → 会被 2.1 拒
3. **新加了权限吗？** 加了 → Privacy 段必须更新
4. **元数据里出现 Apple 产品名了吗？** 出现 → 5.2.5 风险

---

## 1.0.12（2026-11-21）— 已提交审核

```markdown
## What this build (1.0.12) changes

This release is **connection and notification polish only**. No new data is
collected and no new permissions are requested beyond notifications, which the
app already used in previous versions.

- **Faster connections**: the app now keeps several known addresses for the same
  computer and automatically picks the fastest reachable one. When your phone is
  on the same Wi-Fi as the computer, it uses the local address (no relay); when
  you are away, it falls back to your tunnel. A switch in Settings can turn this
  off if you prefer to pick manually.
- **Smoother scrolling in long conversations**: only the most recent few
  messages are rendered as full rich text; older ones are drawn as compact
  plain-text summaries. This eliminated the frame drops we measured while
  scrolling large conversations.
- **Connection screen reordered**: the Connect button now sits directly under
  the saved-addresses list (one tap instead of scrolling to the bottom), the QR
  scanner moved below it, and manual address entry is collapsed by default.
- **Completion reminders now arrive while the phone is locked**: the app
  performs a background refresh, notices when a long-running AI task has
  finished, and posts a local notification. It also shows the beginning of the
  assistant's reply instead of a generic "waiting for you" line, and repeated
  completions in the same conversation replace the previous notification
  instead of stacking up.
DSH Pocket is a client for **DeepSeek Harness (DSH)**, an open-source AI coding
agent that the user runs on their own computer. The app has no account system
and runs no server: it connects directly to the user's own Mac over the local
network or a tunnel they create, using an access PIN they set.

## How reviewers can test everything without a computer

The app ships a **built-in Demo mode** with sample data:

1. Launch the app (first screen is the connection screen);
2. Tap **「体验演示模式」** (Demo mode);
3. You can browse sample sessions, open a conversation, see assistant replies,
   tool-progress rows, Markdown and image thumbnails;
4. Sending a message in Demo mode shows a local echo and a canned reply — no
   network is used.

Demo mode never connects anywhere; a banner at the top says
"演示模式 · 示例数据，未连接电脑".

To check the notification behaviour described above without a computer:
open Settings → 完成提醒 (completion alerts) and enable it; then send a message
in Demo mode and leave the app. The demo session completes on its own and posts
a local notification — this path never contacts a server.

## Full functionality (optional)

Full functionality requires the user's own computer running DSH with the plugin
`dsh-pocket-ios` (https://github.com/jqlong17/dsh-pocket-ios). The plugin shows a
QR code; the app scans it or accepts the LAN address plus an access PIN.

## Privacy

- No analytics, no ads, no accounts, no data collection.
- **Camera**: only used to scan the pairing QR code shown on the user's own
  computer. Frames are processed on-device and never transmitted.
- **Photo library**: only when the user picks an image to send — it goes to the
  user's own computer, not to us.
- **Local network**: required to reach the user's computer; no traffic leaves
  the local network unless the user configured a tunnel themselves.
- **Notifications**: local notifications only, scheduled on-device. No data
  leaves the device for this feature.
- Server address, PIN and session cookies stay on the device (Keychain);
  diagnostics stay in the app sandbox.
- The app does not collect or transmit any data to the developer.

Support: https://dsh-pocket-ios.pages.dev/support
Privacy: https://dsh-pocket-ios.pages.dev/privacy
Contact: jqlong@foxmail.com
```

---

## 1.0.10（2026-11-18，READY_FOR_SALE）

**原样取自 App Store Connect**（注意：正文里写的是 `1.0.6`，说明当时复制上一版没改版本号——下次注意改这行）。

```markdown
## What this build (1.0.6) changes

This release is **performance and interaction polish only**. No new data is collected and no new permissions are requested.

- **Performance**: lower memory footprint when repeatedly entering and leaving a session; tool/process bodies are loaded on demand instead of being kept in memory.
- **Interaction**: expanding or collapsing the process (tool-call) list no longer scrolls or flashes the conversation; the "needs your confirmation" card now appears only while the question is actually pending; a more compact composer puts photo/camera under the left plus button; the session list gained a search field.
- **Connection errors** are now specific: a timeout or a dropped network says "retry, no need to re-pair", while an expired pairing code or wrong PIN says to scan again. No data is sent anywhere; all of this is local messaging.


DSH Pocket is a client for **DeepSeek Harness (DSH)**, an open-source AI coding agent that the user runs on their own computer. The app has no account system and runs no server: it connects directly to the user's own Mac over the local network or a tunnel they create, using an access PIN they set.

## How reviewers can test everything without a computer

The app ships a **built-in Demo mode** with sample data:

1. Launch the app (first screen is the connection screen);
2. Tap **「体验演示模式」** (Demo mode);
3. You can browse sample sessions, open a conversation, see assistant replies, tool-progress rows, Markdown and image thumbnails;
4. Sending a message in Demo mode shows a local echo and a canned reply — no network is used.

Demo mode never connects anywhere; a banner at the top says "演示模式 · 示例数据，未连接电脑".

## Full functionality (optional)

Full functionality requires the user's own computer running DSH with the free `dsh-pocket` plugin (https://github.com/shaobeichen/dsh-pocket). The plugin displays a QR code and a PIN; the app scans it or accepts the LAN address (`http://<computer-ip>:<port>`, default port 3081) plus PIN.

## Privacy

- No analytics, no ads, no accounts, no data collection.
- Server address and session cookies stay on the device; diagnostics stay in the app sandbox.
- Photos are sent only when the user picks one and taps send — to the user's own computer.
- The app does not collect or transmit any data to the developer.

Support: https://dsh-pocket-ios.pages.dev/support
Privacy: https://dsh-pocket-ios.pages.dev/privacy
Contact: jqlong@foxmail.com

## Metadata / trademark note (Guideline 5.2.5)

The App Store metadata does not use Apple product names or imply Apple endorsement. The previous English subtitle contained the word "iPhone"; it has been replaced with "Your coding agent, on the go", and promotional text/description now say "phone" instead. Screenshots show the app's own UI only.
```

---

## 联系方式（每次都要填，未变过）

```
contactFirstName: 嘉奇
contactLastName:  龙
contactEmail:     jqlong@foxmail.com
contactPhone:     +8615910522590
demoAccountRequired: false
demoAccountName:  （留空）
demoAccountPassword: （留空）
```

**`demoAccountRequired` 必须是 `false`**：我们填的是「演示模式」而不是账号密码，勾 `true` 会要求填用户名密码，反而没有入口。

---

## 怎么拉历史文案

脚本在 `/tmp/asc-review.mjs`（不在仓库里，凭证不入库）。逻辑：

```bash
# 用 ASC API Key 换 JWT，然后
GET /v1/apps?filter[bundleId]=com.ruska.dsh-pocket-ios          → app id
GET /v1/apps/{id}/appStoreVersions?limit=5                      → 各版本 id
GET /v1/appStoreVersions/{versionId}/appStoreReviewDetail       → notes / demo 账号
```

凭证在 `~/.zshrc`（`ASC_KEY_ID` / `ASC_ISSUER_ID`）+ `~/.appstoreconnect/private_keys/AuthKey_CKPJTSH2KX.p8`。

**提交后记得回填**：`appStoreReviewDetail` 是**可写**的，所以下次提交完可以反过来把线上值拉回来核对，
避免「本地记的和线上不一致」。

---

## 踩过的坑

1. **版本号忘改**：1.0.10 的 notes 第一行写的是 `1.0.6`——复制上一版时漏改。**每次提交前搜一遍 `## What this build` 后面的版本号**。
2. **重试会创建新的 review submission**：App Store Connect 的提交分三步（`reviewSubmissions` → `reviewSubmissionItems` → `PATCH submitted`），
   中途失败重跑会多出一个空的 submission，需要先查再决定复用哪个。
3. **`Invalid Pre-Release Train`**：版本号已经被关掉（closed）时不能再传同版本，必须升。
