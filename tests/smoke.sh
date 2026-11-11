#!/bin/sh
# smoke.sh — 守住「文档写了但代码没有」这类漂移，不做功能测试。
#   sh tests/smoke.sh      # 0 = 通过
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
fail=0

say() { printf '%-58s %s\n' "$1" "$2"; }

# 1. 每个 src/cdtk-* 都能给出用法（--help 或直接运行打印 usage）
for f in "$REPO"/src/cdtk-*; do
    n=$(basename "$f")
    case $n in
        cdtk-doctor) say "help: $n" "skip (no -h by design)"; continue;;
        cdtk-notify) out=$(cd "$REPO/src" && sh "$f" 2>&1);;
        *) out=$(cd "$REPO/src" && python3 "$f" --help 2>&1);;
    esac
    case $out in
        *Usage*|*usage:*|*用法*) say "help: $n" "ok";;
        *) say "help: $n" "FAIL"; fail=1;;
    esac
done

# 2. README 里反引号内的 --flag 必须真的被对应脚本的 argparse 声明过。
#    用 ast 收集每个脚本 add_argument 的 option strings，再与文档求差；
#    源码里只在注释/help 文本中出现的 flag 不算数（旧版直接查源码子串，会假阴性）。
python3 - "$REPO" <<'PY' || fail=1
import ast, re, sys, pathlib
repo = pathlib.Path(sys.argv[1])
bad = 0
FENCE = re.compile(r"^\s*```")

def options_of(tool):
    """返回该脚本 add_argument 声明的全部 option strings；无 argparse 或解析失败返回 None。"""
    src = repo / "src" / tool
    if not src.exists():
        return None
    try:
        tree = ast.parse(src.read_text(encoding="utf-8", errors="ignore"))
    except SyntaxError:
        return None
    opts = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and getattr(node.func, "attr", "") == "add_argument":
            for a in node.args:
                if isinstance(a, ast.Constant) and isinstance(a.value, str) and a.value.startswith("-"):
                    opts.add(a.value)
    return opts

def doc_flags(text):
    """按 (tool, flag) 归集文档里的 flag：反引号片段 + 围栏代码块，shell 注释部分不计。"""
    out = []
    in_fence = False
    for line in text.splitlines():
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        m = re.search(r"cdtk-([a-z]+)", line)
        if not m:
            continue
        tool = "cdtk-" + m.group(1)
        if in_fence:
            chunks = [line.split("#", 1)[0]]           # 代码块里 # 之后是注释，不算
        else:
            chunks = re.findall(r"`([^`]*)`", line)    # 正文只认反引号内的内容
        for chunk in chunks:
            for flag in re.findall(r"--[a-z][a-z-]+", chunk):
                out.append((tool, flag))
    return out

cache = {}
for doc in [repo/"README.md", repo/"README_zh.md"]:
    docbad = 0
    for tool, flag in doc_flags(doc.read_text(encoding="utf-8")):
        if tool not in cache:
            cache[tool] = options_of(tool)
        opts = cache[tool]
        if opts is None or not opts:
            print(f"flag: {tool} {flag}".ljust(58) + "skip (no argparse)"); continue
        if flag in opts:
            continue
        print(f"flag: {tool} {flag}".ljust(58) + "FAIL"); docbad = 1; bad = 1
    print(f"flags: {doc.name}".ljust(58) + ("FAIL" if docbad else "ok"))
sys.exit(bad)
PY

# 3. setup.sh 注册的工具集合 == README 工具表里的集合
setup_tools=$(sed -n 's/^for tool in //p' "$REPO/src/setup.sh" | sed 's/;.*//' | tr ' ' '\n' | grep '^cdtk-' | sort -u)
doc_tools=$(grep -h '^| `cdtk-' "$REPO/README.md" | sed 's/^| `\([a-z-]*\)`.*/\1/' | sort -u)
if [ "$setup_tools" = "$doc_tools" ]; then
    say "tool list: setup.sh == README" "ok"
else
    say "tool list: setup.sh == README" "FAIL"
    printf '  only in setup.sh: %s\n  only in README:   %s\n' \
        "$(comm -23 "$(printf '%s\n' "$setup_tools")" "$(printf '%s\n' "$doc_tools")" | tr '\n' ' ')" \
        "$(comm -13 "$(printf '%s\n' "$setup_tools")" "$(printf '%s\n' "$doc_tools")" | tr '\n' ' ')"
    fail=1
fi

[ "$fail" -eq 0 ] && echo "smoke: PASS" || echo "smoke: FAIL"
exit "$fail"
