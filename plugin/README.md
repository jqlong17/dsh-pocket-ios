# dsh-pocket-ios（DSH 插件）

在 DSH 的**设置 → 手机访问**里加入 iOS 客户端下载二维码与连接引导，把「手机访问」和
[DSH Pocket iOS](https://github.com/jqlong17/dsh-pocket-ios) 串起来。

## 它做什么

- 设置页新增「iOS 客户端」入口（`settings.section` 插槽，原生渲染）；
- 在「手机访问」页的**局域网访问上方**尽力插入一张 iOS 卡片：下载二维码 + Release 链接 +
  源码 zip 直链（DOM 注入，插入失败不影响上面的原生入口）；
- `dependencies` 带 `dsh-pocket`，安装本插件会一并安装手机访问所需的 dsh-pocket。

## 安装

```bash
# 从 npm 安装（会自动带上依赖 dsh-pocket）
dsh plugin add dsh-pocket-ios
```

npm: <https://www.npmjs.com/package/dsh-pocket-ios>

安装后重启 DSH（或按提示重启），打开 **设置 → 手机访问** 即可看到 iOS 入口。

> 为什么依赖 dsh-pocket 而不是复制它的 patch：复制上游 patch 会在上游变更时失真，且用户
> 单独安装 dsh-pocket 时会产生重复插件行；依赖 + 官方安装命令更稳。

## 手机端

iOS App 通过 GitHub Release 分发（自签安装）：

<https://github.com/jqlong17/dsh-pocket-ios/releases>

装好后在 App 里扫描 dsh-pocket 的二维码即可连接本机 DSH。

## 许可

GPL-2.0（与上游 dsh-pocket 一致）。
