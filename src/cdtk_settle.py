"""
settle.py — 移植自 iCTRL 的 ScreenSettle（XCUITest 版），改成纯截图比对。

原版：OpenMinis/iCTRL · iCTRLUITests/ScreenSettle.swift
      只依赖「小尺寸灰度/彩色帧」的两两比较，不依赖无障碍树、也不依赖 XCUITest，
      所以整套判定逻辑可以原样搬到 CoreDevice 上——截图能力我们本来就有。

为什么值得搬：点击之后「界面有没有动、动完没有」这件事，之前只能靠 sleep 猜。
这套算法用 36x78 的粗网格吸收 JPEG 噪声，再用几条阈值区分
「没反应 / 在动 / 动完了 / 一直在动（视频）/ 换页了」。
"""
import time

from PIL import Image

GRID_W, GRID_H = 36, 78
SKIP_TOP_ROWS = 5          # 状态栏自己会变，不算 App 反应
PIXEL_DELTA = 14           # 单格亮度/色差超过这个才算变化
CHANGED_SHARE = 0.02       # 与动作前的帧相比，变化超过 2% 才算"屏幕变了"
QUIET_SHARE = 0.01         # 相邻两帧差异低于 1% → 静止
STEADY_TOLERANCE = 0.02
STEADY_CEILING = 0.40
NEW_SCREEN_SHARE = 0.25    # 变化超过 25% → 像是换页/弹层
LOCAL_CHANGED_SHARE = 0.12 # 点击点附近变化的占比阈值
INTERVAL = 0.15            # 两帧之间停顿


class Frame:
    """一张 36x78 的 RGBA 粗网格。"""
    __slots__ = ("px",)

    def __init__(self, px):
        self.px = px


def frame_from_png(path):
    """把 PNG 缩成 36x78 的粗网格（等价于原版 frame(from:)）。"""
    im = Image.open(path).convert("RGB").resize((GRID_W, GRID_H), Image.BILINEAR)
    return Frame(im.tobytes())


def _differs(a, b, i, j=None):
    if j is None:
        j = i
    o, p = i * 3, j * 3
    return (abs(a.px[o] - b.px[p]) > PIXEL_DELTA
            or abs(a.px[o + 1] - b.px[p + 1]) > PIXEL_DELTA
            or abs(a.px[o + 2] - b.px[p + 2]) > PIXEL_DELTA)


def diff(a, b, ignore=None):
    """状态栏以下，两帧的差异占比。"""
    start = SKIP_TOP_ROWS * GRID_W
    total = GRID_W * GRID_H
    changed = 0
    n = 0
    for i in range(start, total):
        if ignore is not None and ignore[i]:
            continue
        n += 1
        if _differs(a, b, i):
            changed += 1
    return changed / n if n else 0.0


def local_diff(a, b, px_pt, screen):
    """点击点附近（±24pt）的差异占比 —— 一个开关/勾选变小得看不见。"""
    if px_pt is None or screen[0] <= 0:
        return 0.0
    p = px_pt
    cx = int(p[0] / screen[0] * GRID_W)
    cy = int(p[1] / screen[1] * GRID_H)
    rx = max(1, int(24 / screen[0] * GRID_W))
    ry = max(1, int(24 / screen[1] * GRID_H))
    y_lo = max(cy - ry, SKIP_TOP_ROWS)
    y_hi = min(cy + ry, GRID_H - 1)
    x_lo = max(cx - rx, 0)
    x_hi = min(cx + rx, GRID_W - 1)
    if y_lo > y_hi or x_lo > x_hi:
        return 0.0
    changed = total = 0
    for y in range(y_lo, y_hi + 1):
        for x in range(x_lo, x_hi + 1):
            total += 1
            if _differs(a, b, y * GRID_W + x):
                changed += 1
    return changed / total if total else 0.0


def changed_box(a, b):
    x0, y0, x1, y1 = GRID_W, GRID_H, -1, -1
    for y in range(SKIP_TOP_ROWS, GRID_H):
        for x in range(GRID_W):
            if _differs(a, b, y * GRID_W + x):
                x0, x1 = min(x0, x), max(x1, x)
                y0, y1 = min(y0, y), max(y1, y)
    return None if x1 < 0 else (x0, y0, x1, y1)


def _iou(a, b):
    ix = max(0, min(a[2], b[2]) - max(a[0], b[0]) + 1)
    iy = max(0, min(a[3], b[3]) - max(a[1], b[1]) + 1)
    inter = ix * iy
    area = lambda r: (r[2] - r[0] + 1) * (r[3] - r[1] + 1)
    union = area(a) + area(b) - inter
    return inter / union if union else 0.0


async def wait_settled(sample, budget=3.0, quiet=0.6, baseline=None,
                       focus=None, screen=(1170, 2532)):
    """等界面稳定。

    sample: async 无参函数，返回 Frame 或 None（每次调用抓一张小图）
    返回 dict: stable / changed / waited_ms / samples / last_change_pct
                / first_change_ms / continuous_motion / new_screen
    """
    clock = time.monotonic
    start = clock()
    prev = None
    prev_diff = None
    recent = []
    prev_box = None
    same_region = 0
    motion = False
    changed = False
    first_change = None
    new_screen = False
    samples = 0
    last_diff = 0.0
    capture_cost = 0.15

    def outcome(stable):
        return {
            "stable": stable,
            "changed": None if baseline is None else changed,
            "waited_ms": int((clock() - start) * 1000),
            "samples": samples,
            "last_change_pct": round(last_diff * 100, 1),
            "first_change_ms": None if first_change is None else int(first_change * 1000),
            "continuous_motion": motion,
            "new_screen": new_screen,
        }

    while True:
        t0 = clock()
        cur = await sample()
        if cur is None:
            return outcome(False)
        cost = clock() - t0
        capture_cost = (capture_cost + cost) / 2
        samples += 1

        if baseline is not None:
            d0 = diff(baseline, cur)
            if not changed and (d0 >= CHANGED_SHARE
                                or local_diff(baseline, cur, focus, screen) >= LOCAL_CHANGED_SHARE):
                changed = True
                first_change = clock() - start
            if d0 >= NEW_SCREEN_SHARE:
                new_screen = True

        elapsed = clock() - start
        if prev is not None:
            d = diff(prev, cur)
            last_diff = d
            recent.append(d)
            if len(recent) > 3:
                recent.pop(0)

            playing = (len(recent) == 3
                       and all(x >= STEADY_CEILING for x in recent)
                       and (max(recent) - min(recent)) <= 0.1)

            box = changed_box(prev, cur)
            if box is not None and prev_box is not None:
                area = ((box[2] - box[0] + 1) * (box[3] - box[1] + 1)) / (GRID_W * (GRID_H - SKIP_TOP_ROWS))
                if area < 0.6 and _iou(box, prev_box) >= 0.8:
                    same_region += 1
                else:
                    same_region = 0
            else:
                same_region = 0
            prev_box = box

            past_animations = ((elapsed - first_change >= 0.5) if first_change is not None
                               else elapsed >= 0.5)
            if same_region >= 2 and d < 0.6 and past_animations:
                playing = True
            if playing:
                motion = True

            steady = (d < QUIET_SHARE
                      or (d < STEADY_CEILING and prev_diff is not None
                          and abs(prev_diff - d) <= STEADY_TOLERANCE)
                      or playing)
            prev_diff = d

            watched_enough = (not new_screen) or (first_change is None) or (elapsed - first_change >= 0.5)
            blank_new_screen = new_screen and _is_blank(cur) and (
                first_change is None or elapsed - first_change < 1.0)

            if steady and watched_enough and not blank_new_screen and (changed or elapsed >= quiet):
                return outcome(True)

        prev = cur
        wait = (INTERVAL - cost) if cost < INTERVAL else 0
        if elapsed + wait + capture_cost > budget:
            return outcome(False)
        if wait > 0:
            await _sleep(wait)


async def _sleep(sec):
    import asyncio
    await asyncio.sleep(sec)


def _is_blank(f):
    """≥90% 的格子都和中间那格同色 → 还没画出来的空白页。"""
    start = SKIP_TOP_ROWS * GRID_W
    total = GRID_W * GRID_H
    ref = (start + total) // 2
    same = sum(1 for i in range(start, total) if not _differs(f, f, i, ref))
    return same / (total - start) >= 0.9
