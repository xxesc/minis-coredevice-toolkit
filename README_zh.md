# CoreDevice ToolKit (CDTK) 📱⚡

> **iPhone 单机免电脑、免越狱底层系统控制与开发者工具箱**  
> *Native, Computer-less & Non-Jailbroken iOS System Automation, Sideloading, Diagnostics & Inspection Suite.*

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![MinisSkills PR](https://img.shields.io/badge/MinisSkills-PR%20%23105%20under%20review-yellow.svg)](https://github.com/OpenMinis/MinisSkills/pull/105)
[![Platform: iOS 18+ (Verified) | iOS 17.x (Experimental)](https://img.shields.io/badge/iOS-18.0%2B%20(Verified)%20%7C%2017.x%20(Exp)-blue.svg)]()
[![Namespace: cdtk](https://img.shields.io/badge/Namespace-cdtk--*-green.svg)]()
[![Security: Hardened](https://img.shields.io/badge/Security-Hardened%20(0700%20%7C%20stdin%20PSK)-red.svg)]()
[![Loopback: Surge](https://img.shields.io/badge/Loopback-Surge%20(10.7.0.1%20reflect)-orange.svg)]()

**[English](README.md)** | **[中文说明文档](README_zh.md)**

> 本工具链已以 PR 形式提交至 **[OpenMinis/MinisSkills](https://github.com/OpenMinis/MinisSkills/pull/105)**（审核中），运行于 iOS 原生 AI 与 Linux 容器宿主 **[Minis](https://github.com/OpenMinis)**（iSH / Alpine Linux）环境中。

---

## 🌟 简介 (Overview)

在以往的 iOS 体系中，诸如**本地侧载直装开发应用、模拟硬件物理触控、穿透提取自签沙盒数据、读取电池真实物理循环、WebKit 远程页面调试**等操作，要么需要一台连着 USB 数据线的 Mac/PC 电脑，要么需要设备处于越狱状态。

**`coredevice-toolkit` (`cdtk`)** 彻底打破了这一限制：
通过在 iOS 内部借助 **VPN 本地回环反射 (`10.7.0.1 = reflect`)**，配合 **Node.js TLS-PSK 桥接** 与 **`pmd-pytcp` 纯用户态协议栈**，在 iPhone 单机内部构建起一条“插回手机自己的虚拟数据线”。直接在 **[Minis](https://github.com/OpenMinis) (iSH / Alpine Linux)** 环境中与苹果系统底层 CoreDevice RSD（Remote Service Discovery）守护进程安全握手，将全套系统级底层开发者能力沉淀为纯粹、模块化的 Linux CLI 工具矩阵（`cdtk-*`）。

---

## 🏗️ 架构拓扑 (Architecture)

```text
+-----------------------------------------------------------------------+
|                             iPhone (iOS)                              |
|                                                                       |
|  +---------------------------+       +-----------------------------+  |
|  |       Minis / iSH         |       |    VPN / 回环网卡接口        |  |
|  |     (用户态 Linux 环境)    |       |  (Surge 本地回环反射)        |  |
|  |  -----------------------  |       |  [IP Rewrite / 本地反射]    |  |
|  |   cdtk-* 工具链矩阵       |       |  10.7.0.1 = reflect         |  |
|  |            |              |       +--------------+--------------+  |
|  |            v              |                      ^                 |
|  |   coredevice_session.py   |                      |                 |
|  |   (0700 沙盒 + stdin PSK) |                      |                 |
|  |            |              |                      |                 |
|  |            v              |                      |                 |
|  |   pmd-pytcp 用户态协议栈   |======================+                 |
|  |  (Userspace TCP / Tunnel) |      (虚拟本地自回环隧道数据流)           |
|  +------------+--------------+                                        |
|               |                                                       |
|               v                                                       |
|  +-----------------------------------------------------------------+  |
|  |            iOS CoreDevice RSD 守护服务集群 (RemoteXPC)           |  |
|  |  -------------------------------------------------------------  |  |
|  |  • com.apple.mobile.installation_proxy  (应用安装、侧载与卸载)   |  |
|  |  • dtuhidd / universalhidservice        (底层物理触控注入)       |  |
|  |  • com.apple.coredevice.appservice      (进程监控与应用调度)     |  |
|  |  • com.apple.mobile.house_arrest        (应用沙盒穿透提取)       |  |
|  |  • com.apple.mobile.MCInstall           (描述文件免确认安装管理) |  |
|  |  • com.apple.crashreportcopymobile      (系统崩溃 IPS 日志透视)  |  |
|  |  • com.apple.webinspector               (全局 WebKit 远程调试)   |  |
|  +-----------------------------------------------------------------+  |
+-----------------------------------------------------------------------+
```

---

## 🛡️ 安全加固与实事求是规范 (Security & Truthfulness)

本工具箱在实现黑科技的同时，严格恪守工业级安全标准与实事求是的技术边界：

1. **零进程泄密 (No Command-line Leaks)**：
   - TLS-PSK 密钥严禁通过命令行参数 (`argv`) 传递，彻底杜绝 `ps -ef` 进程嗅探。PSK 统一由主进程通过私密 `stdin` 管道直接投递给 Node.js 桥接进程。
2. **私有临时沙盒隔离 (Private Sandboxing)**：
   - 彻底废除固定 `/tmp` 文件，所有 Unix Domain Socket 通信均建立在 `tempfile.mkdtemp(0700)` 属主独占隔离目录内，退出时强制双重清理，防劫持、防残留。
3. **配对凭证 Ed25519 权限检测与自愈**：
   - 配对记录包含核心签名私钥。工具链内置权限健康检测，当发现外部挂载卷权限过宽（`0644`）时，自动将其安全复制隔离进属主独占私有沙盒 `/root/.cdtk/pairing/` 并锁定为 `0600`。
4. **单点 `/32` 路由范围隔离**：
   - 路由规则 `10.7.0.1/32` 仅捕获该单个虚拟 IP，不有意捕获局域网或互联网流量；自定义规则集请自行核对顺序。
5. **系统版本实事求是说明**：
   - **已实测验证 (Verified)**：`iOS 18.0+`（作者真机验证）；
   - **实验性支持 (Experimental)**：`iOS 17.0 ~ 17.7`（早期小版本系统 `remoted` 可能仅绑定 IPv6 Link-Local 或存在端口漂移，欢迎社区测试反馈）。

---

## 🛠️ 工具矩阵 (`cdtk-*`)

| 工具命令 | 底层服务 / 协议 | 核心能力说明 |
| :--- | :--- | :--- |
| **`cdtk-doctor`** | `diagnostic` + `self-repair` | **环境体检医生**：一键秒级检测系统依赖、Python 模块、配对凭据合规性、本地回环通道与亮屏握手，对异常项输出精准修复建议 |
| **`cdtk-install`** | `installation_proxy` + `zsign` | **免电脑开发侧载**：自动识别 IPA，本地 P12 证书快速重签，秒级直装进 iOS |
| **`cdtk-ctrl`** | `dtuhidd` + `appservice` | **硬件级自动化控制**：枚举物理输入设备，向屏幕注入真实物理按压与滑动流，进程监控与 App 冷启动 |
| **`cdtk-profile`** | `MCInstall` | **描述文件管理**：免跳转 Safari、免输入密码，一键安装/移除描述文件与自签根证书 |
| **`cdtk-fs`** | `house_arrest` + `afc` | **沙盒穿透与媒体管理**：免越狱穿透提取自签/开发 App 的全量容器（Documents/Library），管理媒体分区 |
| **`cdtk-diag`** | `diagnostics_relay` + `syslog` | **硬件自检与系统日志**：直读电池出厂设计容量、真实物理最大容量、放电循环次数；实时捕获内核 syslog |
| **`cdtk-crash`** | `crashreportcopymobile` | **崩溃与闪退透视器**：秒级抓取系统全量 `.ips` 崩溃日志，结构化解析异常代码与触发线程 Backtrace |
| **`cdtk-inspect`** | `webinspector` | **WebKit 远程穿透**：列出系统挂载的 WebKit 实例与公开页面，注入执行 JS、提取 Cookies 与 Storage |
| **`cdtk-springboard`** | `springboard.iconstate` | **主屏桌面编排**：备份、提取、编排与热恢复 iOS 桌面主屏图标和文件夹布局 |
| **`cdtk-proc`** | `dtservicehub` + `processcontrol` | **进程控制与内存豁免**：免越狱为目标应用申请内核级 Jetsam 内存查杀豁免，注入进程暂停/恢复信号 |

---

## 🚀 快速上手 (Getting Started)

### 1. 前置条件 (Prerequisites)

1. **iOS 设备**：运行 iOS 18.0+（或 iOS 17.x），系统【设置 ➡️ 隐私与安全性】已开启「开发者模式」；
2. **Minis App**：提供 Alpine Linux 运行环境；
3. **本地回环基建**：在 **Surge** 中开启 `10.7.0.1 = reflect`（详见 [Surge 本地回环指南](references/SURGE_LOOPBACK_zh.md)）；
4. **配对文件 (`pairing.plist`)**：通过电脑或 SideStore/Jitterbug 导出配对记录，放置于 `/var/minis/workspace/cdtk/`（详见 [配对指南](references/PAIRING_GUIDE_zh.md)）。

---

### 2. 免编译极速初始化安装

在终端中执行：

```bash
git clone https://github.com/xxesc/minis-coredevice-toolkit.git /var/minis/workspace/coredevice-toolkit
cd /var/minis/workspace/coredevice-toolkit/src
sh setup.sh
```

*(基于 Alpine 预编译包与纯 Python 协议栈，规避 gcc 与 sslpsk-pmd3 编译；实际耗时取决于网络。)*

---

### 3. 一键环境体检诊断 (`cdtk-doctor`)

执行内置的体检医生（支持 `--zh` 中文输出）：

```bash
cdtk-doctor --zh
```

示例输出（示意数据，已脱敏）：
```text
🩺 CoreDevice RSD 极客工具链环境体检医生 (cdtk-doctor)
==================================================================

1. 检查基础系统运行时与命令依赖:
  ✅ [通过] Node.js 运行时: /usr/bin/node (v22.23.2)
  ✅ [通过] Python 运行时: /usr/bin/python3 (3.12.15)

2. 检查 Python 核心协议栈模块:
  ✅ [通过] Python 模块 [cryptography] 已就绪
  ✅ [通过] Python 模块 [pmd_pytcp] 已就绪
  ✅ [通过] Python 模块 [pymobiledevice3] 已就绪
  ✅ [通过] Python 模块 [coredevice_session] 已就绪

3. 检查设备配对凭据 (.plist):
  ✅ [通过] 发现配对文件: /root/.cdtk/pairing/my_device.plist
  ✅ [通过] 配对文件安全权限合规 (0600 属主独占)
  ✅ [通过] 设备标识符 (UDID): 00008110-001A2B3C4D5E6F7A

4. 检查本地回环网络通道 (10.7.0.1:49152):
  ✅ [通过] 本地回环端口连通成功 (10.7.0.1:49152)

5. 检查与 iOS 内核 Remote Services 握手通信:
  ✅ [通过] 苹果底层 Pair-Verify 协议握手成功 (PSK 协商正常)
  ✅ [通过] iPhone 处于解锁亮屏与开发者就绪状态

==================================================================
🎉 全套环境体检通过，CDTK 已就绪。
```

---

## 📖 常用指令速查 (CLI Cheat Sheet)

### 1. 电池硬件与电源状态 (`cdtk-diag`)
```bash
cdtk-diag hw
```

### 2. 进程生命周期与硬件触控 (`cdtk-ctrl`)
```bash
cdtk-ctrl procs --apps-only          # 列出所有正在运行的前后台 App
cdtk-ctrl launch com.apple.Preferences # 冷启动系统设置
cdtk-ctrl tap 300 500                # 向屏幕物理坐标 (300, 500) 注入真实硬件点击
cdtk-ctrl swipe 300 800 300 200      # 硬件级平滑滑动轨迹流
```

### 3. 免电脑侧载与自签名 (`cdtk-install`)
```bash
cdtk-install list                    # 枚举已安装的第三方应用
cdtk-install install app.ipa -b com.example.demo -n "我的分身" # 自动重签并直装
cdtk-install uninstall com.example.demo -y # 原生反注册干净卸载
```

### 4. 描述文件免跳转静默管理 (`cdtk-profile`)
```bash
cdtk-profile list                    # 枚举系统已安装的描述文件
cdtk-profile install cert.mobileconfig -y # 静默安装证书或配置
cdtk-profile remove <PayloadIdentifier> -y # 静默移除指定的描述文件
```

### 5. 系统崩溃日志分析 (`cdtk-crash`)
```bash
cdtk-crash list -n 10                # 列出最近 10 份崩溃与诊断日志
cdtk-crash view <crash_file.ips>     # 结构化深度解析异常代码与线程堆栈
```

---

## 📄 开源许可证 (License)

本项目基于 [MIT License](LICENSE) 许可协议发布。
