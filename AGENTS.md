# DSH Pocket iOS · 协作入口

任何 AI 在这个仓库里改代码之前，先读这两处，再动手。

## 1. 写代码的规矩（主流程）

真源：`/Users/ruska/projects/skill/代码编写规范/`

| 文件 | 作用 |
| --- | --- |
| `README.md` | 目录索引与阅读路径 |
| `代码编写执行规范.md` | **主流程**：七条原则、八步流程、提交清单 |
| `版本检查点规范.md` | 大改动前后的 git 检查点、JSONL 记录、脚本 |
| `ios架构设计规范.md` | 分层 / 垂直切片 / 依赖方向 / 阈值 / 反模式 |
| `ios交互设计规范.md` | 界面哲学 / 场景细则 / 可执行数值 |
| `开源项目参考规范.md` | 动手前怎么参考高 star 项目，抄思路不抄代码 |

**最短版**：非豁免改动先写 `spec/NN-*.md` → 先写失败测试 → 实现 → 全量测试 → 回看 spec。

## 2. 本仓库的约定

- **spec 目录**：`spec/NN-主题.md`（已有 01–10，编号递增）。
- **测试**：`cd DSHKit && swift test`；App 编译 `xcodebuild build -scheme DSHPocket`。
- **检查点**：大改动前后各打一次，记录只追加。

  ```bash
  ./scripts/record-checkpoint.sh baseline --note "开始做 <主题>"
  # ...改代码、跑测试、提交主改动...
  ./scripts/record-checkpoint.sh result --spec spec/NN-xxx.md --tests "swift test NNN 绿"
  ./scripts/verify-checkpoints.sh
  ```

  记录文件 `git-checkpoints.jsonl`，每行的 `commit` 就是那次提交的完整 sha。
  规则：先提交主改动拿到 sha，再写记录；**不要 amend 合并**（会重算 sha 导致记录失效）。

## 3. 硬性禁止

- 不要把公网地址、token、凭证写进代码或日志（历史已因此重写过一次）。
- 不要新增 `+Feature` extension 堆叠（那是假拆分，见架构规范）。
- 不要用 `.system(size:)` 硬编码字号（用系统文本样式，见交互规范）。
- 不要在小改动里夹带无关重构（漂移是主要回归来源）。
