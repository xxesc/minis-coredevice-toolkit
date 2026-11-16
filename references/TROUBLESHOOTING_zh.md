# 排障

主 README 只列症状，这里是完整判断依据与操作步骤。

> 所有「实测」均为单机单次观察，没有 CI 复现。

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

这是**主动杀**，不是协议冲突的副作用。`--no-kill` 传下去是 `terminateExisting: false`，
系统看到实例已存在就直接切前台，不走终止那一步。同一设备同一 App 连续四次 `launch`
的 PID 对照（目标 `com.anthropic.claude`，非宿主，测量时不碰宿主自己）：

| 调用 | 返回 PID |
| ---- | -------- |
| `launch`（默认） | 10129 |
| `launch`（默认，再来一次） | **10130** ← 换新进程 |
| `launch --no-kill` | 10130 |
| `launch --no-kill`（再来一次） | **10130** ← 不动 |

**规则**：拉起别的 App 随便用；切回宿主用 `cdtk-ctrl launch <宿主 bundle id> --no-kill`（只激活不杀），
或人工点图标。不想弹「请先勿触碰屏幕」横幅加 `--no-notify`。

**别跟 Q2 混为一谈**。两件事症状像、原因不同：

| | 触发 | 表现 | 解法 |
| --- | --- | --- | --- |
| 本条 | `launch` 省略 `--no-kill` | 宿主进程被**主动终止**后重启，PID 变、界面「已中断」 | 加 `--no-kill` |
| Q2 | 两条 cdtk 命令**同时**跑 | 后到的踩死先到的，报 `ConnectionRefused` / `0 bytes read` | 串行执行（已有跨进程锁） |

加 `--no-kill` 之后回宿主是安全的：进程不重启，正在跑的 shell 命令和会话上下文都不受影响。
把宿主切到后台的也不是 `launch`，是 iOS 的后台挂起策略。

**Q6：命令跑完后隧道还占资源吗**

不占。每条命令是独立进程，退出即释放 RSD 会话和 Node 子进程（单机观察：退出后 1 秒内查不到残留进程与监听端口）。
正常退出不会留目录；被 `timeout` 或 SIGKILL 打断的会话会剩下一个含 `relay.sock` 的目录；`cdtk-doctor` 每次启动清理一天以上、且进程已不在的（`--no-sweep` 可跳过清理）。
`/tmp/.cdtk_rsd_port.json` 端口缓存是设计如此，会保留。

**Q7：第三方输入法下文本输入支持不完善**

同一串 `minis skills`，纯 HID 按键、不点屏幕键盘：

| 当前键盘 | 实际结果 |
| --- | --- |
| 第三方输入法（实测豆包） | `minisskills` —— 空格被吞；拼音态下字母还会变成汉字；`Cmd+V` 也被它接管 |
| 苹果自带 English (US) | `Minis skills` —— 正常（`M` 是系统自动首字母大写） |

**这是键盘扩展的行为，不是隧道问题，不要往 RSD / HID 层查。**

CDTK 的应对：

- `input` 遇空格或非 ASCII 自动改走剪贴板（`--no-paste` 强制键盘）；
- `paste` 粘完回读屏幕，没落进输入框就明确报错；
- 输入法接管 `Cmd+V` 时没有自动办法，只能手动「长按输入框 → 粘贴」；
- App 无法指定键盘（`isSecureTextEntry` 会遮点、禁粘贴）；要稳定输入请在「设置 → 通用 → 键盘」里删除或关闭第三方键盘。

---
