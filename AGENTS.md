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

**最短版**：非豁免改动先写 `spec/NN-*.md`（含预估工时）→ 先写失败测试 → 实现 → 全量测试 → 回看 spec。

**接手旧 spec 先校验格式**：按七段对照，缺段先补（历史 spec 多缺「参考实现」与「预估工时」），测试计划要标 target。

## 2. 本仓库的约定

- **spec 目录**：`spec/NN-主题.md`（已有 01–10，编号递增）。
- **测试**：`cd DSHKit && swift test`；App 编译走模拟器（真机锁屏常不可达）：
  `xcodebuild build -scheme DSHPocket -destination 'platform=iOS Simulator,id=2BD221E6-CFAA-4E90-8BEB-E7392ACCCB19'`
- **功能验证**：`ios_sim_boot` → `simctl install/launch` → 演示模式走会话列表与对话视图。
- **检查点**：大改动前后各打一次，记录只追加。

  ```bash
  ./scripts/record-checkpoint.sh baseline --spec spec/NN-xxx.md --estimate 90   # 预估分钟
  # ...改代码、跑测试、提交主改动...
  ./scripts/record-checkpoint.sh result --spec spec/NN-xxx.md --tests "swift test NNN 绿"
  ./scripts/verify-checkpoints.sh
  ./scripts/estimate-accuracy.sh   # 预估 vs 实际，输出倍率中位数用于下次校准
  ```

  记录文件 `git-checkpoints.jsonl`，每行的 `commit` 就是那次提交的完整 sha。
  规则：先提交主改动拿到 sha，再写记录；**不要 amend 合并**（会重算 sha 导致记录失效）。

## 3. 架构事实与历程

- `docs/architecture/fact.json`：**脚本生成，禁止手写**。`./scripts/architecture-facts.sh`
- `docs/architecture/journey.jsonl`：架构决策只追加，字段固定。改动分层/抽象时写一条。
- `./scripts/check-architecture.sh`：违规检查，退出码 1。**新增违规当次修掉**，存量按 spec 还债。

当前存量 8 处违规（6 个超 400 行、ConnectionModel 7 个 extension、MotionPolicy 在纯逻辑层 import SwiftUI）。

## 3.5 提交时必须包含工程文件

`DSHPocket.xcodeproj` 在仓库根目录，**不在** `DSHPocket/` 里。新增 Swift 文件后：
- 必须在 `project.pbxproj` 注册（fileRef + group + Sources phase），否则 CI/他人拉下来编译失败；
- `git add` 要显式带上 `DSHPocket.xcodeproj`，只写 `git add DSHPocket` 会漏掉它（已踩两次）。

自检：

```bash
# 工作区每个新增 .swift 都应在 pbxproj 里出现
for f in $(git status --porcelain | awk '$1=="??"{print $2}' | grep '\.swift$'); do
  grep -q "$(basename "$f")" DSHPocket.xcodeproj/project.pbxproj || echo "未注册: $f"
done
```

## 4. 硬性禁止

- 不要把公网地址、token、凭证写进代码或日志（历史已因此重写过一次）。
- 不要新增 `+Feature` extension 堆叠（那是假拆分，见架构规范）。
- 不要用 `.system(size:)` 硬编码字号（用系统文本样式，见交互规范）。
- 不要在小改动里夹带无关重构（漂移是主要回归来源）。
