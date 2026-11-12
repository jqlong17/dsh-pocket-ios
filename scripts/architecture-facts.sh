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

# 违规检查：纯逻辑层不得依赖 UI 框架
ui_frameworks = {"SwiftUI", "UIKit", "AppKit"}
violations = []
for mod in modules:
    if mod["layer"] == "pure-logic":
        for fw in ui_frameworks & set(mod["imports"]):
            violations.append({"rule": "pure-logic-no-ui", "file": mod["file"], "detail": f"导入了 {fw}"})
    if mod["lines"] > 400:
        violations.append({"rule": "file-max-400", "file": mod["file"], "detail": f"{mod['lines']} 行"})

# extension 堆叠检查（≥3 个同前缀 extension 视为假拆分）
by_prefix = collections.defaultdict(list)
for mod in modules:
    base = os.path.basename(mod["file"])
    if "+" in base:
        by_prefix[base.split("+")[0]].append(mod["file"])
for prefix, paths in sorted(by_prefix.items()):
    if len(paths) >= 3:
        violations.append({"rule": "extension-split-smell", "file": prefix + ".swift",
                           "detail": f"{len(paths)} 个 +Feature 文件"})

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
    "violations": violations,
}
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(facts, f, ensure_ascii=False, indent=2)

print(f"已生成 {out_path}")
print(f"  提交 {commit}｜文件 {len(modules)}｜违规 {len(violations)}")
for l in facts["layers"]:
    print(f"    {l['layer']:12} {l['files']:3} 文件 {l['lines']:6} 行")
if violations:
    print("  违规明细（前 10 条）:")
    for v in violations[:10]:
        print(f"    - {v['rule']}: {v['file']} — {v['detail']}")
PY
