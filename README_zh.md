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

- 不是越狱：没有 root，读不了系统分区；只能调用 RSD 暴露出来的服务。
- 需要 Surge（≥ 5.23）把 `10.7.0.1` 反射回本机。
- 需要一个 RemotePairing 格式的配对文件，获取方式见 [配对指南](references/PAIRING_GUIDE_zh.md)。
- 首次运行需要一次 USB 连接（由电脑或任意 USB 主机发起）让 `remoted` 通告 listener；配对记录本身可以纯机内获取（见配对指南）。listener 掉线后的恢复见 Q3。
- 实测环境：iPhone 14（iPhone14,7）/ iOS 27.3，宿主 Minis 1.16。其它版本没有在本仓库验证过。
  仓库没有 CI，也没有可复现的测试脚本，文档里的「实测」都是单机单次观察。

---

## 原理

`cdtk-*` 启动 → 从配对记录取密钥 → 起 Node.js TLS-PSK 桥接 → 在 `pmd-pytcp` 用户态协议栈上连
`10.7.0.1:<rsd_port>` → RSD 握手拿服务表 → 用 RemoteXPC 调具体服务 → 命令结束即拆隧道。

```text
Minis (iSH)                   loopback                    iOS kernel
cdtk-* ── coredevice_session ──► 10.7.0.1:49xxx ──► remoted ──► RSD services
        └ Node TLS-PSK relay + pytcp userspace stack
```

---

## 前置条件

1. iOS 设备，已开启「开发者模式」；
2. 宿主 Minis（iSH / Alpine Linux，aarch64）；
3. Surge ≥ 5.23，按 [回环指南](references/SURGE_LOOPBACK_zh.md) 配置 `10.7.0.1`；
4. 配对文件，放在 `/root/.cdtk/pairing/`（0600）—— 见 [配对指南](references/PAIRING_GUIDE_zh.md)；
5. 一台电脑（只在 listener 掉线需要重插 USB 时用到）。

---

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

它跑六步：运行时、Python 模块、配对文件与权限、回环端口、Pair-Verify 握手，最后**真建一次隧道**（`createListener`）。
只有第 6 步通过才说明通道可用——Pair-Verify 只验 host 签名。有问题会给出修复命令。默认把设备标识符打码，`--show-udid` 才显示完整值。

---

## 工具矩阵

| 命令               | 作用                     |
| ------------------ | ------------------------ |
| `cdtk-doctor`      | 环境体检，清残留目录     |
| `cdtk-install`     | 列应用、装 / 卸 IPA      |
| `cdtk-ctrl`        | 进程、拉起 App、触控     |
| `cdtk-notify`      | 推送系统横幅（仅 Minis） |
| `cdtk-profile`     | 描述文件：列 / 装 / 删   |
| `cdtk-fs`          | 读沙盒、媒体             |
| `cdtk-diag`        | 电池数据、内核日志       |
| `cdtk-crash`       | 列取解析 `.ips`          |
| `cdtk-inspect`     | WebKit 页面、注入 JS     |
| `cdtk-springboard` | 主屏布局备份 / 下发      |
| `cdtk-proc`        | Jetsam 豁免、信号        |

`-h` 对绝大多数命令有效；`cdtk-doctor -h` 不会打印帮助，而是直接开始体检，`cdtk-notify` 用无参数运行看用法。

`cdtk-install` 优先用 `zsign` 签名；找不到时自动回退 `rcodesign`：解包 IPA → 换 `embedded.mobileprovision` →
按描述文件 entitlements 签 bundle → 重打包。密码可以写成 `密码：xxx`，会自动剥掉前缀。

---

## 常用命令

```bash
cdtk-diag hw                                # 电池健康
cdtk-ctrl procs --apps-only                 # 正在跑的 App
cdtk-ctrl launch com.example.demo           # 拉起 App
cdtk-ctrl tap 585 642                       # 像素坐标（原生竖屏，与截图一致）
cdtk-ctrl swipe 585 1800 585 600            # 滑动
cdtk-install list
cdtk-install info com.example.demo          # 签名主体、沙盒路径、App Groups
cdtk-install install app.ipa -y             # 直装（-y 必填）
cdtk-install install app.ipa -y -s -b com.example.demo2 -n "Demo2"   # 换 bundle id 必须加 -s
cdtk-crash list -n 10
cdtk-crash view <file.ips>
cdtk-profile list
```

需要确认的命令：`install`、`uninstall`、`profile install/remove`、`proc signal` 不给 `-y` 直接拒绝；`springboard apply` 不给 `-y` 会转成交互式确认。
文档里的示例值都是占位符：`com.example.demo` 只是格式演示，与任何真实应用无关。`cdtk-doctor` 里那行 `配对标识` 打印的是配对记录的
`identifier`（UUID），默认已打码，不是设备 UDID。
已知限制：`-b` / `-n` 只在真正签名时生效；已经带签名的 IPA 不给 `-s` 会被静默忽略。

---

## 排障

**Q1：全线报 `ConnectionRefusedError 10.7.0.1:49152`，或「连上了但没回应」**

两种形态，按现象分开判断：

- `RST` / `ConnectionRefused`：那个端口上没有 listener；
- TCP 连上但 0 字节回包：回环层接住了，`remoted` 不答话。Surge < 5.23 会静默丢掉 `[IP Rewrite]`，
  表现就是这样——先确认 Surge 版本和那三行配置。

`coredevice_session` 会探测 RPPairing 魔数来区分「活 listener」和「哑 listener」，并按
`CDTK_RSD_PORT` → `/tmp/.cdtk_rsd_port.json` 缓存 → 49152 → 扫描 49152–65535 的顺序找端口。

**Q2：两条 cdtk 命令同时跑，其中一条「中途断连」或报 0 字节**

`remoted` 对来的连接有一条不通融的规则（iOS 27.x 逻辑，注释见 `pymobiledevice3` 的
`remote/remotexpc.py`）：**按源地址替换** —— 新连接的源 IP 与已有 peer 相同，就先取消那条 peer 的连接，
连握手都还没读。单机回环反射下所有进程源地址都一样，所以同一时刻只允许一条 RSD 会话：

- 后到的把先到的踩死 → 先到的报 `ConnectionRefused` / 中途断连 / `0 bytes read`；
- 端口扫描（向成千个端口建连）会连番替换，几乎必然踩掉另一个会话。

**已内置跨进程互斥**：`CoreDeviceSession` 进出隧道全程持有 `/tmp/.cdtk_session.lock`（`flock`），
后到的命令打印「另一条 cdtk 会话正在使用设备，排队等待…」后串行执行；`cdtk-doctor` 的第 4–6 步
（扫描 + 真握手 + 建隧道）持同一把锁。默认排队上限 120 秒，超时报 `另一条 cdtk 会话占用设备超过 120s`。

| 环境变量            | 作用                                     |
| ------------------- | ---------------------------------------- |
| `CDTK_LOCK_TIMEOUT` | 排队上限秒数，默认 120，`0` = 不限时     |
| `CDTK_LOCK_FILE`    | 锁文件路径，默认 `/tmp/.cdtk_session.lock` |
| `CDTK_NO_LOCK=1`    | 关掉互斥（只在你自行保证串行时用）       |

要让多条命令真正并行，得给每条会话分配**不同的回环源地址**（各自的代理反射规则），
仅靠进程隔离是做不到的。

**Q3：确认回环正常（有 RPPairing 回包）之后仍然没有 listener**

说明 `remoted` 关掉了监听（双身份 re-attach / 锁屏挂起 / 被并发会话踩掉）。这时解锁、重启手机、
重连代理都没用，可靠的办法是用数据线重插一次 USB。先确认不是 Q2 那种自踩：
`pgrep -f cdtk-` 看有没有残留进程，`cdtk-doctor` 会清理一天以上、进程已不在的残留会话目录。

**Q4：握手身份**

`remoted` 记得每个 peer 的握手 UUID，UUID 变了就 re-attach，一次性关掉该 peer 通告过的全部 listener。
本工具链在 pair-verify 和 RSD 握手里都用配对记录的 `identifier`；`CDTK_HOST_UUID` 可覆盖，`CDTK_DEBUG=1` 打印实际值。

| 环境变量              | 作用                 |
| --------------------- | -------------------- |
| `CDTK_RSD_PORT`       | 固定控制端口，不扫描 |
| `CDTK_RSD_SCAN=0`     | 关闭扫描             |
| `CDTK_RSD_SCAN_RANGE` | 缩小扫描范围         |
| `CDTK_HOST_UUID`      | 覆盖握手身份         |
| `CDTK_DEBUG=1`        | 打印调试信息         |

**Q5：用 `cdtk-ctrl launch` 把宿主 App 自己拉回前台，进程被杀**

宿主 App 指正在跑本工具链的那个 App。`cdtk-ctrl launch` 默认 `kill_existing=True`
（源码 `launch_application(bundle_id, kill_existing=not args.no_kill)`），会**先杀掉目标 App 的现有实例再拉起**。
拉起宿主自己 = 自杀：界面报中断，日志里 PID 跳变、没有退出流程，系统崩溃目录里没有对应 `.ips`。

**规则**：拉起别的 App 随便用；切回宿主用 `cdtk-ctrl launch <宿主 bundle id> --no-kill`（只激活不杀），
或人工点图标。不想弹「请先勿触碰屏幕」横幅加 `--no-notify`。

**Q6：命令跑完后隧道还占资源吗**

不占。每条命令是独立进程，退出即释放 RSD 会话和 Node 子进程（单机观察：退出后 1 秒内查不到残留进程与监听端口）。
正常退出不会留目录；被 `timeout` 或 SIGKILL 打断的会话会剩下一个含 `relay.sock` 的目录；`cdtk-doctor` 每次启动清理一天以上、且进程已不在的（`--no-sweep` 可跳过清理）。
`/tmp/.cdtk_rsd_port.json` 端口缓存是设计如此，会保留。

---

## 安全

- **配对文件**：搜索顺序是 `CDTK_PAIRING_FILE` → `/root/.cdtk/pairing/`（0600）→ `/var/minis/workspace/cdtk/`。
  最后一个在 Minis 里是所有会话共享的目录，权限自负；推荐只放前两个位置。
- **不要提交配对记录**：`*.plist` 里是设备签名私钥，任何情况下都不要放进仓库或公开分享。
- **PSK**：通过 stdin 交给 Node 子进程，不出现在命令行参数里。
- **临时目录**：每次会话 `mkdtemp` + `0700`；正常退出删除，被外部杀掉会留下空目录。
- **路由**：只新增 `10.7.0.1/32` 这一条主机路由用于捕获回环地址，不改动其它路由规则。

---

## 做成技能（给别的助手用）

仓库里没有放 `SKILL.md`（那是每个宿主自己的技能格式），但给了模板。三步：

1. 建目录，把脚本拷进去（目录名叫什么无所谓，`setup.sh` 按自身位置找文件）：

   ```bash
   mkdir -p <skills>/coredevice-toolkit/scripts
   cp -r src/* <skills>/coredevice-toolkit/scripts/
   ```

2. 用 `SKILL.example.md` 生成 `SKILL.md`，按需改 `name` / `description` / 触发词：

   ```bash
   cp SKILL.example.md <skills>/coredevice-toolkit/SKILL.md
   ```

3. 安装并自检：

   ```bash
   sh <skills>/coredevice-toolkit/scripts/setup.sh
   cdtk-doctor
   ```

有三件事 AI 自己办不到，需要人配合：开开发者模式、配好 Surge 回环、导出一份配对文件（StikPair 或 wloc）。
这三样不给，`cdtk-doctor` 第 3–6 步不会通过。

## 维护

改代码或改文档后跑一次：

```bash
sh tests/smoke.sh
```

它检查三件事：每个工具都能打印用法、README 里出现的每个 `--flag` 在对应脚本里真实存在、`setup.sh` 注册的工具集合与工具表一致。它不碰设备，也不联网。

## 许可

[MIT](LICENSE)
