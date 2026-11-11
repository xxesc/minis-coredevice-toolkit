---
name: coredevice-toolkit
description: "iOS 免电脑免越狱的 CoreDevice RSD 工具链（CDTK）：本地回环 + TLS-PSK 桥接 + 用户态协议栈，在 iPhone 单机内建开发者隧道。用于侧载装/卸 IPA、硬件级点按、读写沙盒、描述文件、主屏、进程豁免、崩溃与电池诊断。"
triggers: "cdtk,CoreDevice,侧载,装IPA,自签,沙盒,崩溃,描述文件,电池"
compatibility: "iOS 27.3 (实测) · iSH/Alpine aarch64 · Node.js 18+ · Python 3.10+ · Surge ≥ 5.23"
---

<!--
  用法：把本文件复制成技能的 SKILL.md，按需改 name / description / triggers。
  目录约定：
    <skills>/coredevice-toolkit/SKILL.md        ← 本文件
    <skills>/coredevice-toolkit/scripts/        ← 仓库 src/ 里的全部脚本
  仓库地址：https://github.com/xxesc/minis-coredevice-toolkit
  限制：description ≤ 200 字符；triggers ≤ 50（按 ", " 归一化计数：Σ词长 + 2×(词数−1)）。
-->

# CoreDevice RSD 工具链 (CDTK)

在 iPhone 单机上、不需要电脑也不需要越狱，用 `cdtk-*` 命令操作 iOS CoreDevice（RSD）服务。

## 什么时候用它

- 给这台手机装 / 卸 IPA（本地签名直装），用 `cdtk-install`
- 在真机上注入点按、滑动、拉起 App，用 `cdtk-ctrl`
- 读某个 App 的沙盒（Documents / Library）或媒体分区，用 `cdtk-fs`
- 看崩溃日志、电池数据、系统日志，用 `cdtk-crash` / `cdtk-diag`
- 管理描述文件、编排主屏布局、给进程加 Jetsam 豁免，用 `cdtk-profile` / `cdtk-springboard` / `cdtk-proc`

## 前置条件（缺一不可，且都需要人来做）

1. iPhone，已开启「开发者模式」；
2. Surge ≥ 5.23，按 `references/SURGE_LOOPBACK.md` 配好 `10.7.0.1` 回环；
3. 一份 RemotePairing 配对文件（StikPair 或 wloc 导出），放到 `/root/.cdtk/pairing/`，权限 `0600`；
4. 宿主是 Minis（iSH / Alpine Linux，aarch64）。

## 安装与自检

```bash
sh scripts/setup.sh      # 装依赖并注册 cdtk-* 到 /usr/local/bin
cdtk-doctor              # 六步体检，最后一步真建一次隧道
```

`cdtk-doctor` 会做六项检查：运行时、Python 模块、配对文件与权限、回环端口、Pair-Verify 握手、`createListener` 真隧道。
**只有第 6 步通过才说明通道能用**（Pair-Verify 只验 host 签名）。任何一项 ❌ 都会给出修复命令。

## 常用命令

```bash
cdtk-install list                    # 已装 App（-a 含系统应用）
cdtk-install install app.ipa -y      # 本地签名直装；zsign 缺失时自动回退 rcodesign
cdtk-ctrl procs --apps-only          # 正在跑的 App
cdtk-ctrl tap 585 642                # 像素坐标（原生竖屏，与截图一致）
cdtk-fs app pull com.example.app Library/Preferences/x.plist ./x.plist
cdtk-crash latest -s                 # 解析最新崩溃并把 .ips 存到 workspace
cdtk-springboard backup layout.plist # 改主屏前先备份
```

破坏性命令（`install` / `uninstall` / `profile install|remove` / `proc signal` / `springboard apply`）必须加 `-y`。
`cdtk-ctrl tap|swipe|launch` 没有 `-y` 门，执行前要确认坐标与界面。

## 注意

- `cdtk-ctrl launch` 默认 `kill_existing=True`：会先杀目标 App 再拉起。切回宿主用
  `cdtk-ctrl launch <宿主 bundle id> --no-kill`（只激活不杀），或人工点图标。
- 工具链只在 Minis 宿主里可用；`cdtk-notify` 依赖 Minis 的 `apple-notification`。
- 配对文件等同于设备调试凭据，不要提交到仓库或上传网盘。
- `setup.sh` 是安装动作：会把 `/usr/local/bin/cdtk-*` 重指向本技能目录并覆盖 site-packages 里的共享库，
  已装过就不要重跑。
