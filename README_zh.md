# CDTK — CoreDevice ToolKit

**在 iPhone 单机上、不需要电脑也不需要越狱，直接用 `cdtk-*` 命令行操作 CoreDevice（RSD）的系统服务。**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Tested on iOS 27.3](https://img.shields.io/badge/Tested-iOS%2027.3-blue.svg)]()
[![Host: Minis / iSH](https://img.shields.io/badge/Host-Minis%20%2F%20iSH-green.svg)]()

**[English](README.md) | 中文**

---

## 这个仓库是什么

一组跑在 Minis（iSH / Alpine Linux）里的命令行工具，通过本地回环 + TLS-PSK 桥接接入 iOS 的
CoreDevice RSD 服务，把「装包、注入触控、读沙盒、看崩溃日志、管理描述文件、读电池数据」这些
通常需要连电脑或越狱才能做的事，变成一条命令。

**边界（先说清楚）**

- 不是越狱：拿不到 root，也读不了系统分区；能做的只是 RSD 暴露出来的那些服务。
- 需要 Surge（或等价方案）把 `10.7.0.1` 反射回本机，需要一个配对文件（pairing record）。
- 实测环境：iPhone 14（iPhone14,7）/ iOS 27.3，宿主 Minis 1.16。更早的 iOS 版本没有在本仓库验证过。
- 上游接口随时可能变：`pymobiledevice3` 升级后某些调用会失效，工具会尽量做能力探测，但不保证。

---

## 原理（一段话）

`cdtk-*` 启动 → 从配对记录取密钥 → 起一个 Node.js TLS-PSK 桥接进程 → 在 `pmd-pytcp` 纯用户态协议栈上
建立到 `10.7.0.1:<rsd_port>` 的隧道 → 用 RSD 握手拿到服务列表 → 通过 `RemoteXPC` 调具体服务
（`installation_proxy` / `dtuhidd` / `house_arrest` / `crashreportcopymobile` …）→ 命令结束即拆隧道。

```text
Minis (iSH)                   回环                      iOS 内核
cdtk-* ── coredevice_session ──► 10.7.0.1:49xxx ──► remoted ──► RSD 服务
        └ Node TLS-PSK 桥接 + pytcp 用户态栈
```

---

## 前置条件

1. iOS 设备，已开启「开发者模式」；
2. 宿主 Minis（iSH / Alpine Linux，aarch64）；
3. Surge ≥ 5.23 或等价回环方案，`10.7.0.1` 反射到本机 —— 见 [Surge 回环指南](references/SURGE_LOOPBACK_zh.md)；
4. 一个 RemotePairing 格式的配对文件，放在 `~/.cdtk/pairing/`（0600）—— 见 [配对指南](references/PAIRING_GUIDE_zh.md)。

---

## 安装

```bash
git clone https://github.com/xxesc/minis-coredevice-toolkit.git
cd minis-coredevice-toolkit/src
sh setup.sh
```

`setup.sh` 会装依赖（`pymobiledevice3` 走 `--no-deps`，跳过需要编译的 `sslpsk-pmd3`），把脚本装到 `/usr/local/bin`。
装完先跑体检：

```bash
cdtk-doctor --zh
```

它逐项检查：Node / Python 运行时、Python 模块、配对文件与权限、回环端口连通性、以及一次真实 RSD 握手。
有问题会直接给修复命令。

---

## 工具矩阵

底层服务：`installation_proxy`、`dtuhidd`、`appservice`、`house_arrest`、`crashreportcopymobile`、
`webinspector`、`MCInstall`、`springboard.iconstate`、`processcontrol`、`diagnostics_relay`。

| 命令               | 作用                       |
| ------------------ | -------------------------- |
| `cdtk-doctor`      | 环境体检，清残留会话目录   |
| `cdtk-install`     | 列应用、装 IPA、卸载       |
| `cdtk-ctrl`        | 列进程、拉起 App、注入触控 |
| `cdtk-notify`      | 调起 App 前后推横幅        |
| `cdtk-profile`     | 列 / 装 / 删描述文件       |
| `cdtk-fs`          | 读沙盒与媒体分区           |
| `cdtk-diag`        | 电池数据、内核日志         |
| `cdtk-crash`       | 列取并解析 `.ips`          |
| `cdtk-inspect`     | 列 WebKit 页面、注入 JS    |
| `cdtk-springboard` | 备份 / 下发主屏布局        |
| `cdtk-proc`        | Jetsam 豁免、发信号        |

---

## 常用命令

```bash
cdtk-diag hw                              # 电池健康
cdtk-ctrl procs --apps-only               # 正在跑的 App
cdtk-ctrl launch com.apple.Preferences    # 拉起系统设置
cdtk-ctrl tap 585 642                     # 像素坐标点击（原生竖屏，与截图一致）
cdtk-ctrl swipe 585 1800 585 600          # 滑动
cdtk-install list
cdtk-install install app.ipa -b com.example.demo -n "Demo"
cdtk-crash list -n 10
cdtk-crash view <file.ips>
cdtk-profile list
```

所有命令都支持 `-h`。

---

## 排障

**Q1：全线报 `ConnectionRefusedError 10.7.0.1:49152`，或「连上了但没回应」**

两种失败形态，只看 TCP 连通性区分不出来：

| 现象                        | 含义                             |
| --------------------------- | -------------------------------- |
| `RST` / `ConnectionRefused` | 该端口的 listener 已经不在了     |
| TCP 连上但 0 字节回包       | 回环层接住了，`remoted` 从不答话 |

`coredevice_session` 会做 RPPairing 指纹（回 `RPPairing` 魔数才算活着），并按
`CDTK_RSD_PORT` → `/tmp/.cdtk_rsd_port.json` 缓存 → 49152 → 扫描 49152–65535 的顺序定位端口。

**Q2：扫描全范围也找不到 listener**

说明 `remoted` 的 listener 已被关闭（双身份 re-attach / 锁屏挂起）。可靠恢复是**用数据线重插一次 USB**；
解锁、重启手机、重连代理都不解决问题。

**Q3：握手身份**

`remoted` 会记住每个 peer 的握手 UUID，UUID 变了就 re-attach，一次性关掉该 peer 通告过的全部 service listener。
本工具链让 pair-verify 与 RSD 握手都出示配对记录里的 `identifier`，可用 `CDTK_HOST_UUID` 覆盖，
`CDTK_DEBUG=1` 打印实际使用的 UUID。

| 环境变量                          | 作用                                 |
| --------------------------------- | ------------------------------------ |
| `CDTK_RSD_PORT`                   | 显式指定控制端口（设置后不自动扫描） |
| `CDTK_RSD_SCAN=0`                 | 关闭自动扫描                         |
| `CDTK_RSD_SCAN_RANGE=49152-50000` | 缩小扫描范围                         |
| `CDTK_HOST_UUID`                  | 覆盖 RSD 握手身份                    |
| `CDTK_DEBUG=1`                    | 打印握手 UUID 等调试信息             |

**Q4：用 `cdtk-ctrl launch` 把宿主 App 自己拉回前台，进程会被杀掉**

宿主 App 指正在运行本工具链的那个 App。用它自己的 bundle id 执行 `cdtk-ctrl launch` 时，进程在回到前台的
一瞬间收到 `SIGKILL`：界面报中断，日志里 PID 直接跳变、没有任何退出流程，系统崩溃目录里也没有对应 `.ips`
（只有 App 自己写的 `FOREGROUND CRASH (SIGKILL — app was in use)`）。

实测（同一进程 PID 贯穿）：

| 切回方式                                              | 结果 |
| ----------------------------------------------------- | ---- |
| `cdtk-ctrl launch <宿主>`                             | 被杀 |
| 人工点图标                                            | 正常 |
| iCTRL `launch_app` / Swipt `device.launchApplication` | 正常 |

原因是它走 DVT / AppService 那条 RSD 服务，对宿主自己调用会触发系统终止；拉起别的 App 不受影响。
**规则**：切走随便用，切回宿主走普通启动路径。

**Q5：命令跑完后隧道还占资源吗**

不占。每条 `cdtk-*` 都是独立进程，退出即释放 RSD 会话与 Node 桥接子进程（实测退出后 1 秒内无残留进程、
无监听端口）。留下的是 `/tmp/.cdtk_rsd_port.json` 端口缓存（按设计复用）和一个空的 `/tmp/cdtk_*` 会话目录
（内含 0 字节 `relay.sock`）；被 `timeout` 强杀的会话才会留下目录，`cdtk-doctor` 会清掉一天以上的。

---

## 安全

- **配对私钥**：只从 `~/.cdtk/pairing/`（0600）读取；权限过宽时会复制进私有目录再锁 0600。
- **PSK**：通过 stdin 投递给 Node 子进程，不出现在命令行参数里。
- **临时目录**：每次会话 `mkdtemp` + `0700`，退出时清理。
- **作用域**：只动 `10.7.0.1/32` 这一条回环路由，不碰局域网与公网流量。

---

## 许可

[MIT](LICENSE)
