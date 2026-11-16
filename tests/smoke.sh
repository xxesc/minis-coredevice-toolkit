#!/bin/sh
# smoke.sh — guards "documented but not implemented" drift. Not a functional test.
#   sh tests/smoke.sh      # 0 = pass
#
# Works in both layouts:
#   <repo>/src/cdtk-*  + README.md / README_zh.md     (standalone repo)
#   <skill>/scripts/cdtk-* + SKILL.md                 (MinisSkills tree)
set -u
# 两种布局都要认：<repo>/tests/smoke.sh（父目录是仓库根）
# 与 <skill>/smoke.sh（自己所在目录就是根）。原来只看 ..，
# 放在技能根目录时会把 /var/minis/skills 当成仓库，直接报 no src/ or scripts/。
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$SELF_DIR/.." && pwd)
[ -d "$SELF_DIR/scripts" ] && [ -n "$(ls "$SELF_DIR"/scripts/cdtk-* 2>/dev/null)" ] && REPO="$SELF_DIR"
fail=0

say() { printf '%-58s %s\n' "$1" "$2"; }

# Locate the code directory and the docs that describe it.
SRC=""
for d in src scripts; do
    [ -d "$REPO/$d" ] && [ -n "$(ls "$REPO/$d"/cdtk-* 2>/dev/null)" ] && { SRC="$REPO/$d"; break; }
done
[ -n "$SRC" ] || { echo "smoke: FAIL (no src/ or scripts/ with cdtk-* tools)"; exit 1; }

# 文档范围：README / SKILL.md，加上 references/ 下的详解文档。
# 排障细节从 README 搬进了 references/TROUBLESHOOTING*.md，
# 所以「文档里提到的东西代码里必须有」这类检查要跟着扩到 references。
DOCS=""
for f in "$REPO/README.md" "$REPO/README_zh.md" "$REPO/SKILL.md"; do
    [ -f "$f" ] && DOCS="$DOCS $f"
done
for f in "$REPO"/references/*.md; do
    [ -f "$f" ] && DOCS="$DOCS $f"
done
[ -n "$DOCS" ] || { echo "smoke: FAIL (no README*.md or SKILL.md)"; exit 1; }

# 1. Every tool prints usage (--help, or usage on bare run for cdtk-notify).
for f in "$SRC"/cdtk-*; do
    n=$(basename "$f")
    case $n in
        cdtk-doctor) say "help: $n" "skip (no -h by design)"; continue;;
        cdtk-notify) out=$(cd "$SRC" && sh "$f" 2>&1);;
        *) out=$(cd "$SRC" && python3 "$f" --help 2>&1);;
    esac
    case $out in
        *Usage*|*usage:*|*用法*) say "help: $n" "ok";;
        *) say "help: $n" "FAIL"; fail=1;;
    esac
done

# 2. Every --flag mentioned next to a tool name in the docs must actually be declared
#    by that tool's argparse. Collects option strings via ast, then diffs against the docs;
#    flags that only appear in comments/help text do not count (the old substring check
#    produced false negatives).
python3 - "$REPO" "$SRC" "$DOCS" <<'PY' || fail=1
import ast, re, sys, pathlib
repo, src = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
docs = [pathlib.Path(p) for p in sys.argv[3].split()]
bad = 0
FENCE = re.compile(r"^\s*```")

def options_of(tool):
    """Return every option string this tool's argparse declares; None if it has none."""
    path = src / tool
    if not path.exists():
        return None
    try:
        tree = ast.parse(path.read_text(encoding="utf-8", errors="ignore"))
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
    """Collect (tool, flag) pairs from the docs: backticked spans and fenced code,
    ignoring anything after '#' inside a fence (that is a shell comment)."""
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
            chunks = [line.split("#", 1)[0]]
        else:
            chunks = re.findall(r"`([^`]*)`", line)
        for chunk in chunks:
            for flag in re.findall(r"--[a-z][a-z-]+", chunk):
                out.append((tool, flag))
    return out

cache = {}
for doc in docs:
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

# 3. The tools setup.sh registers == the tools actually implemented in src/.
#    技能布局（<skill>/scripts/）没有 setup.sh，这一项无从比较，跳过。
if [ -f "$SRC/setup.sh" ]; then
setup_tools=$(sed -n 's/^for tool in //p' "$SRC/setup.sh" | sed 's/;.*//' | tr ' ' '\n' | grep '^cdtk-' | sort -u)
# 检查的是「注册 == 实现」，不再从 README 的工具表格里取名单：README 现在只讲
# 这是什么 / 原理 / 前置条件 / 安装，工具清单进了 `cdtk-* --help`。少装一个脚本或
# setup.sh 漏注册一个，这项都会 FAIL。
src_tools=$(for f in "$SRC"/cdtk-*; do [ -f "$f" ] && basename "$f"; done | sort -u)
if [ "$setup_tools" = "$src_tools" ]; then
    say "tool list: setup.sh == src/" "ok"
else
    say "tool list: setup.sh == src/" "FAIL"
    printf '  only in setup.sh: %s\n' "$(printf '%s\n' $setup_tools | grep -vxF "$(printf '%s\n' $src_tools)" | tr '\n' ' ')"
    printf '  only in src/:     %s\n' "$(printf '%s\n' $src_tools | grep -vxF "$(printf '%s\n' $setup_tools)" | tr '\n' ' ')"
    fail=1
fi
else
    say "tool list: setup.sh == docs" "skip (no setup.sh in this layout)"
fi

# 4. Session-lock guard. remoted replaces a peer by source address, so exactly one RSD
#    session may be live at a time. The lock must exist in code AND be explained in the
#    docs: either side going missing means someone dropped the fix.
python3 - "$REPO" "$SRC" "$DOCS" <<'PY' || fail=1
import sys, pathlib
repo, src = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
docs = sys.argv[3].split()
cds = (src / "coredevice_session.py").read_text(encoding="utf-8")
sess = cds.split("class CoreDeviceSession", 1)[-1]
doc_text = "".join(pathlib.Path(p).read_text(encoding="utf-8") for p in docs)
checks = [
    ("lock: SessionLock defined",  "class SessionLock" in cds),
    ("lock: session_lock helper",  "def session_lock(" in cds),
    ("lock: taken in __aenter__",  "SessionLock()" in sess),
    ("lock: released in __aexit__", "self._release_lock()" in sess),
    ("lock: released on failure",  "_aenter_tunnel" in sess),
    ("doc: CDTK_LOCK_TIMEOUT",     "CDTK_LOCK_TIMEOUT" in doc_text),
    ("doc: source-address rule",   "source address" in doc_text or "源地址" in doc_text),
]
bad = 0
for name, ok in checks:
    print(f"{name}".ljust(58) + ("ok" if ok else "FAIL"))
    bad = bad or (0 if ok else 1)
sys.exit(bad)
PY

# 5. A stale pairing record must be told apart from a dead loopback. If someone collapses the
#    two again, the fix (re-export the record) turns back into "replug USB" advice.
python3 - "$SRC" <<'PY' || fail=1
import sys, pathlib
src = pathlib.Path(sys.argv[1])
cds = (src / "coredevice_session.py").read_text(encoding="utf-8")
checks = [
    ("stale: _is_stale_pairing_failure()", "def _is_stale_pairing_failure(" in cds),
    ("stale: excluded from port scan",     "if _is_stale_pairing_failure(err):" in cds),
    ("stale: own error message",           "配对记录已失效" in cds or "pairing record is stale" in cds.lower()),
]
bad = 0
for name, ok in checks:
    print(f"{name}".ljust(58) + ("ok" if ok else "FAIL"))
    bad = bad or (0 if ok else 1)
sys.exit(bad)
PY

# 5. Q5 的归因不能退回旧说法：必须点明是 kill_existing 主动终止，且与 Q2 的并发互踢分开。
#    Q5 正文现在活在 references/TROUBLESHOOTING*.md，README 只剩四节简介，
#    所以按「全部文档」查：正确说法必须在某处，旧说法必须哪儿都没有。
python3 - $DOCS <<'PYEOF' || fail=1
import sys, pathlib
docs = [pathlib.Path(p) for p in sys.argv[1:]]
text = "".join(p.read_text(encoding="utf-8") for p in docs)
checks = [
    ("q5 cause: docs", "kill_existing" in text and "--no-kill" in text and "Q2" in text),
    ("q5 no old wording (zh)", "对宿主自己调用会触发系统终止" not in text),
    ("q5 no old wording (en)", "calling it on the host itself triggers the termination" not in text),
]
bad = 0
for name, ok in checks:
    print(name.ljust(58) + ("ok" if ok else "FAIL"))
    bad = bad or (0 if ok else 1)
sys.exit(bad)
PYEOF

[ "$fail" -eq 0 ] && echo "smoke: PASS" || echo "smoke: FAIL"
exit "$fail"
