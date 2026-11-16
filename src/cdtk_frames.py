"""快照式取帧：抓一段视频流 → 一次 ffmpeg 解成多张 36x78 小图 → 本地比对。

为什么这样设计（踩过的坑）：
  * 逐张截图 1.4s/张，settle 要好几张，太慢；
  * 常驻 ffmpeg + Popen + terminate() 会把 iSH 的 ffmpeg worker 卡死
    （"a previous ffmpeg operation was aborted and its worker could not be stopped"），
    必须重启 App 才能恢复。
  所以这里 **每次都用 subprocess.run 一次性调用**，绝不 Popen 常驻。

一次调用拿到 N 帧小图，等价于 iCTRL 的视频流取样（它是 0.1s/帧实时抓），
但代价是先把 2 秒录下来，换来的是「一次隧道往返 + 一次 ffmpeg」。
"""
import asyncio
import glob
import os
import shutil
import struct
import subprocess
import tempfile

from pymobiledevice3.remote.core_device.screen_stream import (
    capture_rtp_to_file,
    depacketize_hevc,
)


def _rtp_to_annexb(rtp_path):
    """RTP 文件 → 裸 HEVC 码流（Annex-B）。

    坑：不能把 payload 裸拼，必须先跳过 12 字节 RTP 头 + CSRC + extension，
    再交给官方 depacketize_hevc 处理 FU 分片，否则 ffmpeg 报 Invalid data。
    """
    data = open(rtp_path, "rb").read()
    i = 0
    nals = []
    fu = bytearray()
    while i + 4 <= len(data):
        ln = struct.unpack(">I", data[i:i + 4])[0]
        pkt = data[i + 4:i + 4 + ln]
        i += 4 + ln
        if len(pkt) < 12:
            continue
        cc = (pkt[0] & 0x0F) * 4
        off = 12 + cc
        if pkt[0] & 0x10:                       # RTP extension header
            if off + 4 <= len(pkt):
                ext_len = struct.unpack(">H", pkt[off + 2:off + 4])[0]
                off += 4 + ext_len * 4
        depacketize_hevc(pkt[off:], fu, nals)
    return b"".join(b"\x00\x00\x00\x01" + n for n in nals), len(nals)


async def grab_frames(rsd, duration=2.0, fps=8, grid=(36, 78)):
    """抓一段屏幕视频流，返回 [小图路径...]（按时间顺序）。"""
    work = tempfile.mkdtemp(prefix="cdtkstream_")
    rtp = os.path.join(work, "rtp.bin")
    try:
        await capture_rtp_to_file(rsd, rtp, duration=duration)
        if not os.path.exists(rtp) or os.path.getsize(rtp) < 1000:
            return []
        annexb, nals = _rtp_to_annexb(rtp)
        if not nals:
            return []
        hevc = os.path.join(work, "s.hevc")
        open(hevc, "wb").write(annexb)
        outpat = os.path.join(work, "f_%04d.png")
        # 一次性调用，跑完自己结束 —— 绝不 Popen 常驻
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
             "-f", "hevc", "-i", hevc,
             "-vf", f"fps={fps},scale={grid[0]}:{grid[1]}",
             "-f", "image2", outpat],
            capture_output=True, timeout=120,
        )
        return sorted(glob.glob(os.path.join(work, "f_*.png")))
    finally:
        # 文件留着给调用方用；调用方用完调 cleanup
        pass


def cleanup(paths):
    """删掉连工作目录一起。"""
    if not paths:
        return
    d = os.path.dirname(paths[0])
    if d.startswith(tempfile.gettempdir() + "/cdtkstream_"):
        shutil.rmtree(d, ignore_errors=True)


def frames_to_settle(paths, grid=(36, 78)):
    """小图路径 → 供 cdtk_settle 用的 Frame 序列。"""
    from PIL import Image
    import sys
    _HERE = os.path.dirname(os.path.realpath(__file__))
    if _HERE not in sys.path:
        sys.path.insert(0, _HERE)
    import cdtk_settle as S
    out = []
    for p in paths:
        im = Image.open(p).convert("RGB")
        out.append(S.Frame(im.tobytes()))
    return out
