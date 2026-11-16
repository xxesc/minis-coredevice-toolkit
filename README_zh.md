# CDTK — CoreDevice ToolKit

**在 iPhone 单机上用命令行操作 iOS CoreDevice（RSD）服务：装包、注入触控、读沙盒、看崩溃日志、管描述文件、读电池数据。**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Host: Minis / iSH](https://img.shields.io/badge/Host-Minis%20%2F%20iSH-green.svg)]()

**[English](README.md) | 中文**

---

## 这是什么

一组跑在 Minis（iSH / Alpine Linux）里的命令行工具，通过 Surge 本地回环 + TLS-PSK 桥接接入 iOS 的 CoreDevice RSD 服务，
把通常需要连电脑或越狱才能做的事情变成一条命令。

**边界**

- 不是越狱：没有 root，读不了系统分区，只能调用 RSD 暴露出来的服务。
- 需要 Surge ≥ 5.23 把 `10.7.0.1` 反射回本机（见 [回环指南](references/SURGE_LOOPBACK_zh.md)）。
- 需要一份 RemotePairing 格式的配对文件（见 [配对指南](references/PAIRING_GUIDE_zh.md)）。
- 首次运行需要一次 USB 连接让 `remoted` 通告 listener；配对记录本身可纯机内获取。
- 实测环境：iPhone 14 / iOS 27.3，宿主 Minis 1.16。其它版本未验证。
  仓库没有 CI，「实测」都是单机单次观察。

## 原理

`cdtk-*` 从配对记录取密钥 → 起 Node.js TLS-PSK 桥接 → 在 `pmd-pytcp` 用户态协议栈上连
`10.7.0.1:<rsd_port>` → RSD 握手拿服务表 → 用 RemoteXPC 调具体服务 → 命令结束即拆隧道。

```text
Minis (iSH)                   loopback                    iOS kernel
cdtk-* ── coredevice_session ──► 10.7.0.1:49xxx ──► remoted ──► RSD services
        └ Node TLS-PSK relay + pytcp userspace stack
```

## 前置条件

1. iOS 设备，已开启「开发者模式」；
2. 宿主 Minis（iSH / Alpine Linux，aarch64）；
3. Surge ≥ 5.23，按 [回环指南](references/SURGE_LOOPBACK_zh.md) 配置 `10.7.0.1`；
4. 配对文件放在 `/root/.cdtk/pairing/`（0600），见 [配对指南](references/PAIRING_GUIDE_zh.md)；
5. 一台电脑（只在 listener 掉线需要重插 USB 时用到）。

## 安装

```bash
git clone https://github.com/xxesc/minis-coredevice-toolkit.git
cd minis-coredevice-toolkit/src
sh setup.sh
```

`setup.sh` 装依赖（`pymobiledevice3` 走 `--no-deps`，跳过需要编译的 `sslpsk-pmd3`），把脚本装进 `/usr/local/bin`。

装完先体检：

```bash
cdtk-doctor          # 中文输出加 --zh
```

六步：运行时、Python 模块、配对文件与权限、回环端口、Pair-Verify 握手，最后**真建一次隧道**。
只有第 6 步通过才说明通道可用——Pair-Verify 只验 host 签名。默认打码设备标识符，`--show-udid` 才显示完整值。
