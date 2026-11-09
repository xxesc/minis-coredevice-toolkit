---
name: coredevice-toolkit
description: "iOS 免电脑、免越狱的 CoreDevice RSD 工具链 (CDTK)：通过本地回环 (10.7.0.1=reflect) + Node TLS-PSK 桥接 + pmd-pytcp 用户态协议栈，在 iPhone 单机内建立到苹果底层服务的隧道，提供侧载装包、硬件触控、进程调度、沙盒穿透、描述文件管理、崩溃日志、环境体检等 CLI。实测 iOS 27.3 + Surge。触发词：coredevice-toolkit, cdtk, cdtk-doctor, cdtk-install, cdtk-ctrl, cdtk-fs, cdtk-diag, cdtk-crash, cdtk-profile, cdtk-inspect, cdtk-springboard, cdtk-proc, CoreDevice RSD, iOS 侧载, 手机点按注入。"
compatibility: "iOS 27.3 (实测) · iSH/Alpine aarch64 · Node.js · Python 3.10+ · Surge ≥ 5.23"
---

<!--
  用法：把本文件复制成技能的 SKILL.md，按需改 name / description / 触发词。
  目录约定：
    <skills>/coredevice-toolkit/SKILL.md        ← 本文件
    <skills>/coredevice-toolkit/scripts/        ← 仓库 src/ 里的全部脚本
  仓库地址：https://github.com/xxesc/minis-coredevice-toolkit
-->

# CoreDevice RSD 工具链 (CDTK)

在 iPhone 单机上、不需要电脑也不需要越狱，用 `cdtk-*` 命令操作 iOS CoreDevice（RSD）服务。

## 什么时候用它

- 要给这台手机装 / 卸 IPA（本地签名直装），用 `cdtk-install`
- 要在真机上注入点按、滑动、拉起 App，用 `cdtk-ctrl`
- 要读某个 App 的沙盒（Documents / Library）或媒体分区，用 `cdtk-fs`
- 要看崩溃日志、电池数据、系统日志，用 `cdtk-crash` / `cdtk-diag`
- 要管理描述文件、编排主屏布局、给进程加 Jetsam 豁免，用 `cdtk-profile` / `cdtk-springboard` / `cdtk-proc`

## 前置条件（缺一不可，且都需要人来做）

1. iPhone，已开启「开发者模式」；
2. Surge ≥ 5.23，按 `references/SURGE_LOOPBACK.md` 配好 `10.7.0.1` 回环；
3. 一份 RemotePairing 配对文件（手机上用 StikPair 或 wloc 导出），放到 `/root/.cdtk/pairing/`，权限 `0600`；
4. 宿主是 Minis（iSH / Alpine Linux，aarch64）。

## 安装与自检

```bash
sh scripts/setup.sh      # 装依赖并注册 cdtk-* 到 /usr/local/bin
cdtk-doctor              # 逐项体检：运行时 / 模块 / 配对文件 / 回环 / Pair-Verify 握手
```

`cdtk-doctor` 全绿才算可用；任何一项 ❌ 都会给出修复命令。

## 常用命令

```bash
cdtk-ctrl procs --apps-only          # 正在跑的 App
cdtk-ctrl launch com.example.demo    # 拉起 App
cdtk-ctrl tap 585 642                # 像素坐标（原生竖屏，与截图一致）
cdtk-fs app ls com.example.demo /    # 读沙盒
cdtk-crash list -n 10                # 最近的崩溃日志
cdtk-install list
```

破坏性命令（`install` / `uninstall` / `profile install|remove` / `proc signal`）必须加 `-y`。
完整说明见仓库 README 与 `references/`。

## 注意

- 不要用 `cdtk-ctrl launch` 把**宿主 App 自己**拉回前台，会被系统杀掉；切回用普通启动通道。
- 工具链只在 Minis 宿主里可用；`cdtk-notify` 依赖 Minis 的 `apple-notification`。
- 配对文件等同于设备调试凭据，不要提交到仓库或上传网盘。
