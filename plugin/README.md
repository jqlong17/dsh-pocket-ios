# dsh-pocket-ios（DSH 插件）

在 DSH 的**设置 → 手机访问**里加入 iOS 客户端下载二维码与连接引导，把「手机访问」和
[DSH Pocket iOS](https://github.com/jqlong17/dsh-pocket-ios) 串起来。

当前版本：**0.1.4**（npm `dsh-pocket-ios`）。卡片主按钮与二维码指向 **App Store**（<https://apps.apple.com/app/id6832288744>），
另提供「GitHub 仓库」入口。

## 它做什么

- 设置页新增「iOS 客户端」入口（`settings.section` 插槽，原生渲染）；
- 只在「手机访问」页签内插入一张 iOS 卡片（切到其他页签自动移除）：App Store 下载二维码 +
  App Store / GitHub 仓库入口（DOM 注入，插入失败不影响上面的原生入口）；
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

iOS App 已上架 App Store（免费）：

<https://apps.apple.com/app/id6832288744>

也可以从 [GitHub 仓库](https://github.com/jqlong17/dsh-pocket-ios) 查看源码与发版记录。
装好后在 App 里扫描 dsh-pocket 的二维码即可连接本机 DSH。

## 许可

GPL-2.0（与上游 dsh-pocket 一致），见 [LICENSE](LICENSE)。

注意：本仓库根目录的 `LICENSE`（MIT）只覆盖 `DSHPocket/` iOS 客户端，不覆盖本插件目录。
