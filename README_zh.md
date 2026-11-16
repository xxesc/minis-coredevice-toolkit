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

## 工具矩阵

| 命令               | 作用                     |
| ------------------ | ------------------------ |
| `cdtk-doctor`      | 环境体检，清残留目录     |
| `cdtk-install`     | 列应用、装 / 卸 IPA      |
| `cdtk-ctrl`        | 进程、拉起 App、触控     |
| `cdtk-ui`          | 读界面：元素树、OCR 定位、按文字点 |
| `cdtk-notify`      | 推送系统横幅（仅 Minis） |
| `cdtk-profile`     | 描述文件：列 / 装 / 删   |
| `cdtk-fs`          | 读沙盒、媒体             |
| `cdtk-diag`        | 电池数据、内核日志       |
| `cdtk-crash`       | 列取解析 `.ips`          |
| `cdtk-inspect`     | WebKit 页面、注入 JS     |
| `cdtk-springboard` | 主屏布局备份 / 下发      |
| `cdtk-proc`        | Jetsam 豁免、信号        |

`-h` 对绝大多数命令有效；`cdtk-doctor -h` 会直接开始体检，`cdtk-notify` 无参数运行看用法。
`cdtk-install` 优先用 `zsign` 签名，找不到时回退 `rcodesign`（解包 → 换 profile → 按 entitlements 重签 → 重打包）。

## 常用命令

```bash
cdtk-diag hw                                # 电池健康
cdtk-ctrl procs --apps-only                 # 正在跑的 App
cdtk-ctrl launch com.example.demo           # 拉起 App
cdtk-ctrl tap 585 642                       # 像素坐标（原生竖屏，与截图一致）
cdtk-install install app.ipa -y             # 直装（-y 必填）
cdtk-install info com.example.demo          # 签名主体、沙盒路径、App Groups
cdtk-install install app.ipa -y -s -b com.example.demo2 -n "Demo2"   # 换 bundle id 必须加 -s
cdtk-crash list -n 10
cdtk-profile list
```

写操作（`install` / `uninstall` / `profile install|remove` / `proc signal`）不给 `-y` 直接拒绝；
`springboard apply` 不给 `-y` 会转成交互式确认。示例里的 `com.example.demo` 只是格式占位。

## 界面读写（cdtk-ui）

`cdtk-ctrl` 只按坐标点，不知道屏幕上有什么。`cdtk-ui` 用截图 + OCR 补上这层：
找到文字 → 映射成坐标 → 点击 → 判定界面有没有动、动完没有。

```bash
cdtk-ui tree --app minis                # 可聚焦元素（无障碍标签）
cdtk-ui press "发送"                     # 按文字点；报告「有没有变 / 变了多少 / 动完没有」
cdtk-ui press "某条历史消息" --scroll 4   # 当前屏没有就滚动搜索
cdtk-ui press --at 1042,173              # 纯图标按钮只能给坐标
cdtk-ui grid                             # 截图叠坐标网格，量坐标用
cdtk-ui paste "含空格或中文的内容" --allow  # 走剪贴板，最稳
cdtk-ui input "abc"                      # 纯 ASCII 单词；打完回读校验
```

**定位以 OCR 为主**：元素树滚动相关且不完整（SwiftUI 虚拟化），OCR 只看可见区域，恰好等于「能不能点」。

**`--app` 建议显式给**：审计 daemon 会记住上次的目标进程，切了 App 不给 `--app` 会读到**上一个 App 的元素**，
且完全不报错。匹配优先 `*.app/<同名可执行文件>`，避开 `.appex` / `PlugIns`（Safari 就有 `MobileSafari`
和 `SafariWebExtension` 几个同名进程）。

限制：

- **纯图标按钮**（返回 / 更多选项 / 拷贝 / 发送）屏幕无文字，只能 `grid` 量坐标 + `press --at`。
- **`input` 会自动改走剪贴板**：只要文本含空格或非 ASCII，它就不再键盘打字，直接粘贴。
  键盘输入会被输入法改写——中文拼音态下空格被当「确认候选词」吃掉（`minis skills` → `minisskills`）、
  能拼成拼音的字母变汉字；实测连第三方输入法的英文 QWERTY 态也会吞空格。`--no-paste` 可强制键盘。
- **第三方输入法可能连 `Cmd+V` 也接管**：实测豆包输入法把粘贴内容收进它自己的「剪贴板候选条」，
  输入框一个字都没有。`paste` 现在会回读校验并在没落进输入框时明确报错；遇到就换系统自带键盘。
- **`input --submit` 的回车也可能被吞**，可靠做法是 `press "前往"`。
- 元素坐标拿不到（`Frame` / `AXFrame` 返回 `None`），所以只能绕回坐标点；Safari 这类把内容放在
  WebContent 进程的 App，元素树近乎为空，只能靠 OCR。

## 排障

| 现象 | 指向 |
| --- | --- |
| `ConnectionRefusedError 10.7.0.1:49152`，或连上但 0 字节回包 | Q1 回环或 listener |
| 两条命令同跑，其中一条中途断连 / 报 `0 bytes read` | Q2 并发互踢（已内置锁） |
| 回环有 RPPairing 回包但仍无 listener | Q3 需要重插一次 USB |
| 握手身份变化后 listener 全关 | Q4 `CDTK_HOST_UUID` |
| 把宿主 App 拉回前台后进程被杀、界面「已中断」 | Q5，见下 |
| 命令结束后是否残留资源 | Q6 不占，退出即释放 |

**Q5 一句话**：`cdtk-ctrl launch` 默认 `kill_existing=True`，**先杀再起**；拉起宿主自己就是自杀。
切回宿主必须加 `--no-kill`（传下去是 `terminateExisting: false`）。这和 Q2 是两件事：
本条是**主动终止**，Q2 是两条命令并发、后到的踩死先到的。

完整判断依据、环境变量表、PID 实测对照见 [排障详解](references/TROUBLESHOOTING_zh.md)。

## 安全

- **配对文件**：搜索顺序 `CDTK_PAIRING_FILE` → `/root/.cdtk/pairing/`（0600）→ `/var/minis/workspace/cdtk/`。
  最后一个是 Minis 全局会话共享目录，权限自负，推荐只用前两个。
- **不要提交配对记录**：`*.plist` 里是设备签名私钥。
- **PSK 走 stdin**，不出现在命令行参数里；临时目录 `mkdtemp` + `0700`，正常退出删除。
- **路由**：只新增 `10.7.0.1/32` 一条主机路由，不改动其它规则。

## 做成技能（给别的助手用）

仓库不提供 `SKILL.md`（那是每个宿主自己的格式），只给模板 `SKILL.example.md`：

```bash
mkdir -p <skills>/coredevice-toolkit/scripts
cp -r src/* <skills>/coredevice-toolkit/scripts/
cp SKILL.example.md <skills>/coredevice-toolkit/SKILL.md     # 按需改 name / description / triggers
sh <skills>/coredevice-toolkit/scripts/setup.sh
cdtk-doctor
```

有三件事 AI 自己办不到，需要人配合：开开发者模式、配好 Surge 回环、导出一份配对文件。
这三样不给，`cdtk-doctor` 第 3–6 步不会通过。

## 维护

改完代码或文档跑一次 `sh tests/smoke.sh`（不碰设备、不联网）。它检查：每个工具能打印用法、
文档里出现的每个 `--flag` 在脚本里真实存在、`setup.sh` 注册的工具集合与工具表一致。

## 许可

[MIT](LICENSE)
