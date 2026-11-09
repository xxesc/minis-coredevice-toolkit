# Surge 本地回环配置

**中文 | [English](SURGE_LOOPBACK.md)**

能让 `cdtk-*` 在单机上连到 CoreDevice RSD 的前提，是把 `10.7.0.1` 反射回本机。本仓库只保留这一种已验证的配置方式。

---

## 配置

在 Surge 配置里加三行（`[General]` 两条、`[IP Rewrite]` 一条）：

```ini
[General]
tun-included-routes = 10.7.0.1/32
always-raw-tcp-keywords = "Content-Type: application/pairing+tlv8"

[IP Rewrite]
10.7.0.1 = reflect
```

或者直接用仓库里的模块 [`surge/local-loopback.sgmodule`](../surge/local-loopback.sgmodule)：

```ini
#!name=CoreDevice RSD Local Loopback
#!desc=把 10.7.0.1 反射回本机，供 CDTK 连接 RSD

[General]
tun-included-routes = %APPEND% 10.7.0.1/32
always-raw-tcp-keywords = %APPEND% "Content-Type: application/pairing+tlv8"

[IP Rewrite]
10.7.0.1 = reflect
```

三行各自的作用：

| 配置                                      | 作用                                                                                |
| ----------------------------------------- | ----------------------------------------------------------------------------------- |
| `tun-included-routes = 10.7.0.1/32`       | iOS 默认 `skip-proxy = 10.0.0.0/8` 会绕过 TUN，加这条单主机路由把 `10.7.0.1` 抓回来 |
| `10.7.0.1 = reflect`                      | 把发往该地址的连接反射回本机                                                        |
| `always-raw-tcp-keywords = …pairing+tlv8` | 配对握手是二进制 TLV，别让 Surge 去做 TLS 解密                                      |

作用范围就一条 `/32`，不涉及局域网和公网流量。

---

## 验证

```bash
cdtk-doctor
```

体检第 4 步会连端口，第 5 步做一次真实 Pair-Verify 握手 —— 只有第 5 步过了才算通。

`nc -zv 10.7.0.1 49152` 只能说明端口可达，不能说明 `remoted` 在答话。

---

## 注意

- Surge 5.23 以下的版本会静默丢掉 `[IP Rewrite]`：现象是任何端口都能秒连，但一个字节也收不到。
- 手机需要连着 Wi-Fi；蜂窝网络下 49152 是关闭的。
- 同一时间只能有一个 VPN 生效。
