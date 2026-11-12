#!/usr/bin/env bash
# architecture-facts.sh — 扫描代码，生成当前架构事实快照 docs/architecture/fact.json
#
# 为什么必须是脚本生成的：手写的架构图三个月后必然与代码不符，之后就没人信它。
# 这里只抽「能从代码确定性得到」的事实；意图类信息写在 journey.jsonl。
set -uo pipefail
OUT="${1:-docs/architecture/fact.json}"
mkdir -p "$(dirname "$OUT")"

python3 - "$OUT" << 'PY'
import json, os, re, subprocess, sys, datetime, collections

out_path = sys.argv[1]
root = os.getcwd()

# 分层定义：路径前缀 → 层名与角色
LAYERS = [
    ("DSHKit/Sources", "pure-logic", "纯逻辑层：策略/解析/传输，禁止依赖 UI"),
    ("DSHPocket", "app", "App 编排层与视图"),
    ("DSHPocketUITests", "ui-tests", "端到端 UI 测试"),
]

def layer_of(path):
    for prefix, name, _ in LAYERS:
        if path.startswith(prefix + "/"):
            return name
    return "other"

def iter_swift(base):
    for dirpath, _, files in os.walk(base):
        if "/.build/" in dirpath or "/DerivedData/" in dirpath:
            continue
        for f in files:
            if f.endswith(".swift"):
                yield os.path.join(dirpath, f)

files = []
for base in ["DSHKit/Sources", "DSHPocket", "DSHPocketUITests"]:
    if os.path.isdir(base):
        files.extend(iter_swift(base))

modules = []
imports = collections.defaultdict(set)
for path in sorted(files):
    rel = os.path.relpath(path, root)
    try:
        text = open(path, encoding="utf-8", errors="ignore").read()
    except OSError:
        continue
    lines = text.count("\n") + 1
    layer = layer_of(rel)
    # 顶层类型名（struct/class/enum/actor/protocol），用于模块清单
    types = re.findall(r"^(?:public |internal |private |fileprivate )?(?:final )?(?:struct|class|enum|actor|protocol) (\w+)", text, re.M)
    mods = re.findall(r"^import (\w+)", text, re.M)
    for m in mods:
        imports[layer].add(m)
    modules.append({
        "file": rel,
        "layer": layer,
        "lines": lines,
        "types": types[:12],
        "imports": sorted(set(mods)),
    })

# 依赖关系：层之间 + 层对外部框架
deps = []
for layer, mods in sorted(imports.items()):
    for m in sorted(mods):
        kind = "internal" if m in ("DSHKit", "DSHPocket") else "external"
        deps.append({"from_layer": layer, "to": m, "kind": kind})

# 禁用 API：会 fatalError 的写法（2026-11-12 真机闪退的根因）
# uniqueKeysWithValues 遇到重复 key 是 fatalError，而服务端列表可能重复。
BANNED_PATTERNS = [
    ("duplicate-key-dictionary", "Dictionary(uniqueKeysWithValues:", "改用 Dictionary(_:uniquingKeysWith:)"),
    ("force-unwrap-try", "try!", "改用 try? 或 do-catch"),
    ("force-cast", "as! ", "改用 as? 加兜底"),
]
banned_hits = []
for mod in modules:
    try:
        body = open(mod["file"], encoding="utf-8", errors="ignore").read()
    except OSError:
        continue
    for line_no, line in enumerate(body.split("\n"), 1):
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith("///"):
            continue
        for rule, needle, advice in BANNED_PATTERNS:
            if needle in line:
                banned_hits.append({"rule": rule, "file": mod["file"],
                                    "detail": f"第 {line_no} 行含 {needle.strip()}，{advice}"})

# 机械搬迁残留：同一处出现两个 @MainActor（切函数时常见），编译器会报错，
# 但提前在扫描里报出来能省一次编译往返。
duplicate_attr = []
for mod in modules:
    try:
        body = open(mod["file"], encoding="utf-8", errors="ignore").read()
    except OSError:
        continue
    window = []
    for line_no, line in enumerate(body.split("\n"), 1):
        stripped = line.strip()
        if stripped.startswith("@"):
            window.append((line_no, stripped))
            # 只看最近三行里的注解
            recent = [w for w in window if line_no - w[0] <= 3]
            same = [w for w in recent if w[1] == stripped]
            if len(same) >= 2:
                duplicate_attr.append({"rule": "duplicate-attribute", "file": mod["file"],
                                       "detail": f"第 {line_no} 行重复 {stripped}"})
                window = [(line_no, stripped)]
        elif stripped.startswith("///") or stripped.startswith("//") or not stripped:
            continue
        else:
            window = []

# 字典字面量重复 key（Swift 是 fatalError，不是可选失败）：
# 本项目已踩过三次同类崩溃——服务端重复 sessionId、Dictionary(uniqueKeysWithValues:)、
# L10n 英文字典重复 key（用户切英文即 SIGTRAP）。测试抓不到，只能静态扫。
#
# 只检查 `[String: String] = [...]` 这种扁平文案表：
# - 不用正则跨层扫所有 [...]：那会把数组里嵌套的字典算成同一层，误报一片
#   （实测 PromptPayload 的 "content": [["type": ...]] 就被误判过）；
# - 不用逐行块扫描：单行字典 `["type": "text", ...]` 与后面另一个字典的 key 会串成一块。
duplicate_dict_keys = []
for mod in modules:
    try:
        body = open(mod["file"], encoding="utf-8", errors="ignore").read()
    except OSError:
        continue
    for match in re.finditer(r"\[String: String\]\s*=\s*\[(.*?)\n\s*\]", body, re.S):
        keys = re.findall(r'"((?:[^"\\]|\\.)*)"\s*:', match.group(1))
        seen, dups = set(), set()
        for k in keys:
            if k in seen:
                dups.add(k)
            seen.add(k)
        for d in sorted(dups):
            duplicate_dict_keys.append({
                "rule": "duplicate-dict-key", "file": mod["file"],
                "detail": '字典字面量重复 key：' + d + '（运行时 fatalError）'})

# 无状态类型（spec/2026-11-12-2257 自审结论）：
# 一个类型如果「自有状态字段 = 0」却要注入十几个闭包才能工作，
# 它其实是被拆出来的流程，不是独立单元——用注入模拟「我是那个类的一部分」。
# 判据：自有状态为 0 且注入依赖 > 8。
stateless_smell = []
for mod in modules:
    if "/Session/" not in mod["file"] or "ConnectionModel" in mod["file"]:
        continue
    try:
        body = open(mod["file"], encoding="utf-8", errors="ignore").read()
    except OSError:
        continue
    providers = re.search(r"struct Providers \{(.+?)\n    \}", body, re.S)
    if not providers:
        continue
    injected = len(re.findall(r"\n        var \w+:", providers.group(1)))
    own_state = len(re.findall(r"\n    (?:private\(set\) |private )?var [a-z]\w* (?:=|:)", body))
    # 排掉 Providers 里的字段被误计入
    if injected > 8 and own_state == 0:
        stateless_smell.append({"rule": "stateless-type-smell", "file": mod["file"],
                                "detail": f"自有状态 0 个但要注入 {injected} 个依赖，应改为 extension"})

# 纯转发属性（spec/17）：ConnectionModel 出现 `get { <对象>.<字段> }` 且 set 也只转一手，
# 就是「字段所有权」被藏在了门面后面——调用点看不到自己在跟谁说话，
# 而 SwiftUI 的 @Bindable 根本无法穿过这种转发取绑定（实测会报 let 常量不可赋值）。
FORWARDING_WHITELIST = {
    # 场景核心句柄：模型要持有「当前打开哪个会话」，这不是别人的字段。
    "activeConversation",
}
forwarding_smell = []
for mod in modules:
    if not mod["file"].endswith("ConnectionModel.swift"):
        continue
    try:
        body = open(mod["file"], encoding="utf-8", errors="ignore").read()
    except OSError:
        continue
    for match in re.finditer(r"var (\w+):[^\{\n]*\{\s*\n\s*get \{ \w+\.(\w+) \}", body):
        name = match.group(1)
        if name in FORWARDING_WHITELIST:
            continue
        forwarding_smell.append({"rule": "pure-forwarding-smell", "file": mod["file"],
                                 "detail": f"{name} 只是转发给 {match.group(2)}，调用点应直读"})

# 视图不得穿过模型的纯转发属性（spec/13 批次 3）
# 带副作用的访问器（如 draft 写入要持久化）不算违规；只抓「纯粹是 let 对象的转发」。
PURE_FORWARDING = [
    "isConnected", "errorMessage", "serverAddress", "pin", "isConnecting", "addressNeedsRescan",
    "sessions", "archivedSessionIds", "pinnedSessionIds", "isLoadingSessions",
    "selectedSession", "navigationPath",
    "outboxEntries", "queuedSendRpcIds", "failedSendRpcIds", "ackedSendRpcIds",
]
view_leaks = []
for mod in modules:
    if "/Views/" not in mod["file"]:
        continue
    try:
        body = open(mod["file"], encoding="utf-8", errors="ignore").read()
    except OSError:
        continue
    for name in PURE_FORWARDING:
        if re.search(rf"\bmodel\.{name}\b", body):
            view_leaks.append({"rule": "view-forwards-through-model", "file": mod["file"],
                               "detail": f"model.{name} 应改为直读状态对象"})
            break

# 分层阈值
FILE_LIMITS = {"pure-logic": 400, "app": 600, "ui-tests": 600}

# 违规检查：纯逻辑层不得依赖 UI 框架
ui_frameworks = {"SwiftUI", "UIKit", "AppKit"}
violations = []
for mod in modules:
    if mod["layer"] == "pure-logic":
        for fw in ui_frameworks & set(mod["imports"]):
            violations.append({"rule": "pure-logic-no-ui", "file": mod["file"], "detail": f"导入了 {fw}"})
    # 字典字面量重复 key（Swift 是 fatalError，不是可选失败）：
# 本项目已经踩过三次同类崩溃——服务端重复 sessionId、Dictionary(uniqueKeysWithValues:)、
# L10n 英文字典重复 key（Release 下首次访问即 SIGTRAP）。测试抓不到这类问题，
# 只能靠静态扫描。
# 无状态类型（spec/2026-11-12-2257 自审结论）：
# 一个类型如果「自有状态字段 = 0」却要注入十几个闭包才能工作，
# 它其实是被拆出来的流程，不是独立单元——用注入模拟「我是那个类的一部分」。
# 判据：自有状态为 0 且注入依赖 > 8。
stateless_smell = []
for mod in modules:
    if "/Session/" not in mod["file"] or "ConnectionModel" in mod["file"]:
        continue
    try:
        body = open(mod["file"], encoding="utf-8", errors="ignore").read()
    except OSError:
        continue
    providers = re.search(r"struct Providers \{(.+?)\n    \}", body, re.S)
    if not providers:
        continue
    injected = len(re.findall(r"\n        var \w+:", providers.group(1)))
    own_state = len(re.findall(r"\n    (?:private\(set\) |private )?var [a-z]\w* (?:=|:)", body))
    # 排掉 Providers 里的字段被误计入
    if injected > 8 and own_state == 0:
        stateless_smell.append({"rule": "stateless-type-smell", "file": mod["file"],
                                "detail": f"自有状态 0 个但要注入 {injected} 个依赖，应改为 extension"})

# 纯转发属性（spec/17）：ConnectionModel 出现 `get { <对象>.<字段> }` 且 set 也只转一手，
# 就是「字段所有权」被藏在了门面后面——调用点看不到自己在跟谁说话，
# 而 SwiftUI 的 @Bindable 根本无法穿过这种转发取绑定（实测会报 let 常量不可赋值）。
FORWARDING_WHITELIST = {
    # 场景核心句柄：模型要持有「当前打开哪个会话」，这不是别人的字段。
    "activeConversation",
}
forwarding_smell = []
for mod in modules:
    if not mod["file"].endswith("ConnectionModel.swift"):
        continue
    try:
        body = open(mod["file"], encoding="utf-8", errors="ignore").read()
    except OSError:
        continue
    for match in re.finditer(r"var (\w+):[^\{\n]*\{\s*\n\s*get \{ \w+\.(\w+) \}", body):
        name = match.group(1)
        if name in FORWARDING_WHITELIST:
            continue
        forwarding_smell.append({"rule": "pure-forwarding-smell", "file": mod["file"],
                                 "detail": f"{name} 只是转发给 {match.group(2)}，调用点应直读"})

# 视图不得穿过模型的纯转发属性（spec/13 批次 3）
# 带副作用的访问器（如 draft 写入要持久化）不算违规；只抓「纯粹是 let 对象的转发」。
PURE_FORWARDING = [
    "isConnected", "errorMessage", "serverAddress", "pin", "isConnecting", "addressNeedsRescan",
    "sessions", "archivedSessionIds", "pinnedSessionIds", "isLoadingSessions",
    "selectedSession", "navigationPath",
    "outboxEntries", "queuedSendRpcIds", "failedSendRpcIds", "ackedSendRpcIds",
]
view_leaks = []
for mod in modules:
    if "/Views/" not in mod["file"]:
        continue
    try:
        body = open(mod["file"], encoding="utf-8", errors="ignore").read()
    except OSError:
        continue
    for name in PURE_FORWARDING:
        if re.search(rf"\bmodel\.{name}\b", body):
            view_leaks.append({"rule": "view-forwards-through-model", "file": mod["file"],
                               "detail": f"model.{name} 应改为直读状态对象"})
            break

# 分层阈值：策略层必须短（纯逻辑、可单测），编排层与视图层天然更长。
    # 400 一刀切逼出过 197 行的碎片 extension，改一个功能要跳四个文件，理解成本反而上升。
    # 真正该管的是「一个文件干几件事」，不是行数本身。
    limit = FILE_LIMITS[mod["layer"]]
    if mod["lines"] > limit:
        violations.append({"rule": f"file-max-{limit}", "file": mod["file"],
                           "detail": f"{mod['lines']} 行（{mod['layer']} 阈值 {limit}）"})

# extension 堆叠检查（≥3 个同前缀 extension 视为假拆分）
by_prefix = collections.defaultdict(list)
for mod in modules:
    base = os.path.basename(mod["file"])
    if "+" in base:
        by_prefix[base.split("+")[0]].append(mod["file"])
# 假拆分的判据不是「文件多」，而是「文件多但仍然是同一坨」。
# 按职责拆 extension 在 Swift 里是正常做法；只有当拆出来以后单个文件依然过长
# （说明职责没被真正分开）才值得报警。阈值 600：编排层文件天然比策略层长。
line_of = {mod["file"]: mod["lines"] for mod in modules}
for prefix, paths in sorted(by_prefix.items()):
    if len(paths) < 3:
        continue
    oversized = [p for p in paths if line_of.get(p, 0) > 600]
    if oversized:
        violations.append({"rule": "extension-split-smell", "file": prefix + ".swift",
                           "detail": f"{len(paths)} 个 +Feature 文件，其中 {len(oversized)} 个仍超 600 行"})

try:
    commit = subprocess.check_output(["git", "rev-parse", "--short=7", "HEAD"], text=True).strip()
except Exception:
    commit = None

facts = {
    "generated_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
    "commit": commit,
    "layers": [
        {"layer": name, "role": role,
         "files": sum(1 for m in modules if m["layer"] == name),
         "lines": sum(m["lines"] for m in modules if m["layer"] == name)}
        for prefix, name, role in LAYERS
    ],
    "dependencies": deps,
    "modules": modules,
    "violations": (violations + banned_hits + duplicate_attr + view_leaks
                   + forwarding_smell + stateless_smell + duplicate_dict_keys),
}
all_violations = (violations + banned_hits + duplicate_attr + view_leaks
                  + forwarding_smell + stateless_smell + duplicate_dict_keys)
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(facts, f, ensure_ascii=False, indent=2)

print(f"已生成 {out_path}")
print(f"  提交 {commit}｜文件 {len(modules)}｜违规 {len(all_violations)}")
for l in facts["layers"]:
    print(f"    {l['layer']:12} {l['files']:3} 文件 {l['lines']:6} 行")
if all_violations:
    print("  违规明细（前 10 条）:")
    for v in all_violations[:10]:
        print(f"    - {v['rule']}: {v['file']} — {v['detail']}")
PY
