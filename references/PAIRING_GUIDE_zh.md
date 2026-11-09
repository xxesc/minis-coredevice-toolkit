# 配对记录指南

**[English](PAIRING_GUIDE.md) | 中文**

RSD 隧道靠一份 RemotePairing 记录（`.plist`）完成 SRP / TLS 握手。这份文件是设备级凭据，请按下面的方式保管。

---

## 格式

`load_pairing()` 只认三个顶层键，缺一个就跳过：

| 键            | 类型   | 说明                             |
| ------------- | ------ | -------------------------------- |
| `identifier`  | string | 配对标识，同时作为 RSD 握手 UUID |
| `private_key` | data   | Ed25519 私钥                     |
| `public_key`  | data   | Ed25519 公钥                     |

检查候选文件：

```bash
python3 -c "import plistlib;print(sorted(plistlib.load(open('pairing.plist','rb'))))"
```

---

## 获取

在手机上开启「开发者模式」后，用下面任一 App 配对，再把导出的配对文件（`.plist`）放进搜索路径。两者导出的格式都可用：

| App                           | 说明                         |
| ----------------------------- | ---------------------------- |
| **StikPair**                  | 配对后从 App 内导出 `.plist` |
| **wloc**（`com.yu9191.wloc`） | 同样支持导出配对文件         |

导出文件里应当能看到上面三个键。

其它方式（例如在电脑上用 `pymobiledevice3 remote pair` 生成）本仓库没有验证过，需要时自己试。

> `lockdown` 记录（`/var/db/lockdown/<UDID>.plist`）不是配对记录：它存的是
> `HostCertificate` / `HostPrivateKey` / `RootCertificate`，没有 `identifier` / `private_key` / `public_key`，
> 放进配对目录也用不了。

---

## 存放与搜索顺序

| 顺序 | 位置                                                         |
| ---- | ------------------------------------------------------------ |
| 1    | CLI 参数，如 `cdtk-install --pairing /path/to/pairing.plist` |
| 2    | 环境变量 `CDTK_PAIRING_FILE`                                 |
| 3    | `/root/.cdtk/pairing/*.plist`                                |
| 4    | `/var/minis/workspace/cdtk/*.plist`                          |

当前工作目录默认**不搜索**；要用得显式设 `CDTK_ALLOW_CWD_PAIRING=1`。

---

## 权限

| 情况                  | 行为                                      |
| --------------------- | ----------------------------------------- |
| 权限是 `0600`         | 直接使用                                  |
| 权限过宽（如 `0644`） | 能 `chmod` 就收紧到 `0600`                |
| 文件系统忽略 `chmod`  | 复制到 `/root/.cdtk/pairing/` 再锁 `0600` |

---

## 安全

- 配对记录里是设备签名私钥，拿到它等于拿到开发者级调试权限。不要提交到仓库、不要上传网盘。
- CDTK 不打印私钥和 PSK；但 `cdtk-install --password` 会把**证书密码**（不是配对私钥）传给 `zsign` 命令行，可能短暂出现在 `ps` 里。
