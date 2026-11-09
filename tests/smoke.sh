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

# 2. README 里出现的 --flag 必须真的存在于对应脚本（代码块与反引号都算）
python3 - "$REPO" <<'PYEOF' || fail=1
import re, sys, pathlib
repo = pathlib.Path(sys.argv[1]); bad = 0
for doc in [repo/"README.md", repo/"README_zh.md"]:
    for line in doc.read_text(encoding="utf-8").splitlines():
        m = re.search(r"cdtk-([a-z]+)", line)
        if not m: continue
        tool = "cdtk-" + m.group(1); src = repo/"src"/tool
        if not src.exists(): continue
        for flag in re.findall(r"--[a-z][a-z-]+", line[m.end():]):
            if flag in src.read_text(encoding="utf-8", errors="ignore"): continue
            print(f"flag: {tool} {flag}".ljust(58) + "FAIL"); bad = 1
    print(f"flags: {doc.name}".ljust(58) + ("FAIL" if bad else "ok"))
sys.exit(bad)
PYEOF

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
