# ADR-0003: 长期设备凭证，DSH 重启后自动换票

Date: 2026-11-12
Status: implemented
Commit: 58a1c9f

## Context

DSH 的 `dsh-auth` cookie 是 **session 级**的，进程一重启就失效。
而插件原本只发 **60 秒一次性**配对 token——意味着用户每次重启电脑端都要重新扫码。

这是最影响日常使用的一个摩擦点。

## Decision

三轮凭证：

```
① PIN（首次）
     ↓ 换取
② 长期设备凭证（devices.json，权限 0600）
     ↓ Set-Cookie 下发，App 存 Keychain
③ session cookie（DSH 的）
     ↓ 401 时
    清旧 cookie → 调 /dsh-pocket-ios/refresh → 拿新票 → 静默重连
```

## Alternatives

| 备选 | 否决原因 |
| --- | --- |
| 拉长 cookie 有效期 | 不可控，那是 DSH 核心的决定 |
| 让用户保留 PIN | 体验差，且 PIN 泄露风险高于设备凭证 |

## Consequences

**收益**：DSH 重启 / App 重装 / Tailscale 重启都不再需要扫码。

**代价（都是踩出来的）**：
- 换票请求**必须带 JSON body**（插件在路由前解析 body）
- 换票成功的判定必须是**拿到新 cookie**，不能只看 storage 里有没有旧值
