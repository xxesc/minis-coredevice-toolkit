#!/usr/bin/env python3
"""cdtk-crash 路径解析单元测试（不需要设备）。

回归背景：崩溃日志会被系统从根目录搬进 /Retired，
旧实现拿用户给的文件名直接拼 "/"，导致 pull/view 报
`AFC OBJECT_NOT_FOUND`，只能读到还留在根目录的最新那批。
"""

import importlib.machinery
import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src" / "cdtk-crash"

FAIL = []


def check(name, got, want):
    if got != want:
        FAIL.append(f"{name}: got {got!r}, want {want!r}")
        print(f"FAIL {name}\n  got  {got!r}\n  want {want!r}")
    else:
        print(f"ok   {name}")


def load_module():
    loader = importlib.machinery.SourceFileLoader("cdtk_crash", str(SRC))
    spec = importlib.util.spec_from_loader("cdtk_crash", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def main():
    try:
        mod = load_module()
    except ModuleNotFoundError as e:
        print(f"SKIP: 缺少依赖 {e}（本测试只在有 pymobiledevice3 的环境跑）")
        return 0

    scanned = [
        "/Retired/A-report-2026-11-15-192145.ips",
        "/Retired/B-report-2026-11-16-094107.ips",
        "/C-report-2026-11-16-103000.ips",
    ]
    build = mod.build_candidates

    # 1. 旧日志：裸文件名必须解析到 /Retired 下的真实路径
    cands = build(scanned, "A-report-2026-11-15-192145.ips")
    check("retired-first-candidate", cands[0], "/Retired/A-report-2026-11-15-192145.ips")

    # 2. 同名文件既在根目录又在 /Retired：根目录优先
    dup = ["/Dup-2026-11-16-100000.ips", "/Retired/Dup-2026-11-16-100000.ips"]
    check("root-preferred", build(dup, "Dup-2026-11-16-100000.ips")[0],
          "/Dup-2026-11-16-100000.ips")

    # 3. 显式绝对路径原样优先
    check("absolute-kept", build(scanned, "/Retired/B-report-2026-11-16-094107.ips")[0],
          "/Retired/B-report-2026-11-16-094107.ips")

    # 4. 片段匹配（按扫描顺序=时间倒序）
    check("fuzzy", build(scanned, "094107")[0], "/Retired/B-report-2026-11-16-094107.ips")

    # 5. 完全找不到时给一个根目录兜底候选，便于报错信息可读
    check("fallback", build(scanned, "nope.ips"), ["/nope.ips"])

    # 6. 空输入
    check("empty", build(scanned, "  "), [])

    print()
    if FAIL:
        print(f"{len(FAIL)} 项失败")
        return 1
    print("全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
