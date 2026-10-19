# CoreDevice ToolKit (CDTK) 📱⚡

> **Native, Computer-less & Non-Jailbroken iOS System Automation, Sideloading, Diagnostics & Inspection Suite.**  
> *iPhone 单机免电脑、免越狱底层系统控制与开发者工具箱*

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![MinisSkills PR](https://img.shields.io/badge/MinisSkills-PR%20%23105%20under%20review-yellow.svg)](https://github.com/OpenMinis/MinisSkills/pull/105)
[![Platform: iOS 18+ (Verified) | iOS 17.x (Experimental)](https://img.shields.io/badge/iOS-18.0%2B%20(Verified)%20%7C%2017.x%20(Exp)-blue.svg)]()
[![Namespace: cdtk](https://img.shields.io/badge/Namespace-cdtk--*-green.svg)]()
[![Security: Hardened](https://img.shields.io/badge/Security-Hardened%20(0700%20%7C%20stdin%20PSK)-red.svg)]()
[![Loopback: Surge](https://img.shields.io/badge/Loopback-Surge%20(10.7.0.1%20reflect)-orange.svg)]()

**[English](README.md)** | **[中文说明文档](README_zh.md)**

> This toolkit is submitted to the **[OpenMinis/MinisSkills](https://github.com/OpenMinis/MinisSkills/pull/105)** repository as a pull request under review. It runs inside the on-device Linux host **[Minis](https://github.com/OpenMinis)** (iSH / Alpine Linux) on iOS.

---

## 🌟 Overview

Historically on iOS, operations such as **local sideloading without a computer, injecting hardware-level touch input, penetrating app containers, reading raw battery hardware cycle counts, or inspecting WebKit views** required either a tethered Mac/PC running Xcode or a jailbroken device.

**`coredevice-toolkit` (`cdtk`)** breaks this limitation:
By utilizing **VPN local loopback reflection (`10.7.0.1 = reflect`)** in a compatible proxy app, combined with a **Node.js TLS-PSK relay** and the **`pmd-pytcp` pure userspace protocol stack**, it builds an on-device "virtual USB cable plugged back into the phone itself". Running within **[Minis](https://github.com/OpenMinis)**, it handshakes securely with Apple's CoreDevice RSD (Remote Service Discovery) daemons, providing a modular Linux CLI command matrix (`cdtk-*`).

---

## 🏗️ Architecture

```text
+-----------------------------------------------------------------------+
|                             iPhone (iOS)                              |
|                                                                       |
|  +---------------------------+       +-----------------------------+  |
|  |       Minis / iSH         |       |   VPN / Loopback Interface  |  |
|  |   (Userspace Linux host)  |       |  (Surge Local Loopback)     |  |
|  |  -----------------------  |       |  [IP Rewrite / Reflection]  |  |
|  |   cdtk-* CLI Matrix       |       |  10.7.0.1 = reflect         |  |
|  |            |              |       +--------------+--------------+  |
|  |            v              |                      ^                 |
|  |   coredevice_session.py   |                      |                 |
|  |   (0700 sandbox + PSK in) |                      |                 |
|  |            |              |                      |                 |
|  |            v              |                      |                 |
|  |   pmd-pytcp User Stack    |======================+                 |
|  |  (Userspace TCP / Tunnel) |     (Virtual On-Device Tunnel Flow)    |
|  +------------+--------------+                                        |
|               |                                                       |
|               v                                                       |
|  +-----------------------------------------------------------------+  |
|  |            iOS CoreDevice RSD Daemons (Remote Services)         |  |
|  |  -------------------------------------------------------------  |  |
|  |  • com.apple.mobile.installation_proxy  (Install / Sideload)    |  |
|  |  • dtuhidd / universalhidservice        (Hardware Touch Input)  |  |
|  |  • com.apple.coredevice.appservice      (Process Control / Run) |  |
|  |  • com.apple.mobile.house_arrest        (App Sandbox Extract)   |  |
|  |  • com.apple.mobile.MCInstall           (Profile Staging & Mgmt) |  |
|  |  • com.apple.crashreportcopymobile      (Crash IPS Reports)     |  |
|  |  • com.apple.webinspector               (WebKit Remote Inspect) |  |
|  +-----------------------------------------------------------------+  |
+-----------------------------------------------------------------------+
```

---

## 🛡️ Security & Integrity Specification

1. **Zero Command-Line Leaks**:
   - TLS-PSK pre-shared keys are transferred exclusively via standard input (`stdin`) into Node.js. Keys never appear in `argv` or process listings (`ps -ef`).
2. **Private Sandboxing (0700)**:
   - All Unix domain sockets reside in dedicated `tempfile.mkdtemp(0700)` directories, cleaned up automatically upon exit.
3. **Ed25519 Pairing Record Hardening**:
   - Pairing records (`.plist`) containing private keys are audited for permissions. If stored on external mounts with loose permissions (`0644`), CDTK automatically isolates them into `/root/.cdtk/pairing/` with `chmod 600`.
4. **Single-IP `/32` Route Isolation**:
   - The loopback route `10.7.0.1/32` intercepts only this single virtual IP. It does not intentionally capture LAN or internet traffic; review your own rule order if you use a custom profile.
5. **Truthful Compatibility**:
   - **Verified**: `iOS 18.0+` (Tested end-to-end on physical hardware);
   - **Experimental**: `iOS 17.0 ~ 17.7` (Certain sub-versions may bind exclusively to IPv6 or exhibit port drift).
6. **Upstream SDK Compatibility**:
   - `cdtk-install` probes capabilities instead of hard-coding method names: it prefers `InstallationProxyService.install_from_local(package_path, "Install")` (pymobiledevice3 >= 11.x) and falls back to the legacy `install(ipa_path)`. Upstream renaming `install()` no longer breaks the tool with an `AttributeError`.

---

## 🛠️ CLI Command Matrix (`cdtk-*`)

| Command | Underlying Protocol / Service | Description |
| :--- | :--- | :--- |
| **`cdtk-doctor`** | `diagnostic` + `self-repair` | **Health Doctor**: Audits runtimes, Python modules, pairing files (0600), loopback connectivity, and screen lock status with copy-paste fixes |
| **`cdtk-install`** | `installation_proxy` + `zsign` | **On-Device Sideloading**: Direct signing and installation of IPAs without a computer |
| **`cdtk-ctrl`** | `dtuhidd` + `appservice` | **Hardware Automation**: Injects screen taps, swipes, process orchestration, and app launch |
| **`cdtk-profile`** | `MCInstall` | **Profile Management**: Dispatches and manages `.mobileconfig` profiles via MCInstall directly without Safari redirects; silent for supervised devices (with keybag), requires one-time passcode confirmation in Settings on standard personal devices |
| **`cdtk-fs`** | `house_arrest` + `afc` | **Sandbox & Media Access**: Inspects container filesystems (Documents/Library/SQLite) of sideloaded apps and manages DCIM |
| **`cdtk-diag`** | `diagnostics_relay` + `syslog` | **Hardware Diagnostics**: Reads factory designed capacity, true battery cycle counts, voltage, and real-time kernel syslog |
| **`cdtk-crash`** | `crashreportcopymobile` | **Crash Reporter**: Pulls and structures `.ips` crash logs, exception codes, and stack traces |
| **`cdtk-inspect`** | `webinspector` | **WebKit Remote Inspection**: Inspects open WebKit views, executes dynamic JS, and dumps Cookies/LocalStorage |
| **`cdtk-springboard`** | `springboard.iconstate` | **Home Screen Layout**: Backs up, organizes, and restores home screen icon and folder arrangements |
| **`cdtk-proc`** | `dtservicehub` + `processcontrol` | **Jetsam Memory Waiver**: Grants memory limit waivers (waives Jetsam OOM kills) and sends control signals |

---

## 🚀 Getting Started

### 1. Prerequisites

1. **iOS Device**: iOS 18.0+ (or iOS 17.x), with **Developer Mode** enabled in `Settings -> Privacy & Security -> Developer Mode`;
2. **Minis App**: Provides the Alpine Linux environment on iOS;
3. **Loopback Provider**: Enable `10.7.0.1 = reflect` in **Surge** (see [Surge Loopback Guide](references/SURGE_LOOPBACK.md));
4. **Pairing File (`pairing.plist`)**: Exported from PC/Mac or SideStore/Jitterbug, placed in `/var/minis/workspace/cdtk/` with `chmod 600`.

---

### 2. Zero-Compilation Quick Setup

Run the setup script inside the Minis terminal:

```bash
git clone https://github.com/xxesc/minis-coredevice-toolkit.git /var/minis/workspace/coredevice-toolkit
cd /var/minis/workspace/coredevice-toolkit/src
sh setup.sh
```

*(Uses Alpine precompiled packages and pure Python packages; avoids `gcc` and `sslpsk-pmd3` compilation. Time depends on network speed.)*

---

### 3. Verify Health with `cdtk-doctor`

Run the built-in diagnostic doctor:

```bash
cdtk-doctor
```

Example output (sample data, redacted):
```text
🩺 CoreDevice RSD Geek Toolkit Health Doctor (cdtk-doctor)
==================================================================

1. Checking Base System Runtimes & Commands:
  ✅ [PASS] Node.js Runtime: /usr/bin/node (v22.23.2)
  ✅ [PASS] Python Runtime: /usr/bin/python3 (3.12.15)

2. Checking Python Protocol Stack Modules:
  ✅ [PASS] Python Module [cryptography] is ready
  ✅ [PASS] Python Module [pmd_pytcp] is ready
  ✅ [PASS] Python Module [pymobiledevice3] is ready
  ✅ [PASS] Python Module [coredevice_session] is ready

3. Checking Device Pairing Credentials (.plist):
  ✅ [PASS] Found pairing file: /root/.cdtk/pairing/my_device.plist
  ✅ [PASS] Pairing file security compliant (0600 owner exclusive)
  ✅ [PASS] Device UDID: 00008110-001A2B3C4D5E6F7A

4. Checking Loopback Network Connectivity (10.7.0.1:49152):
  ✅ [PASS] Loopback port reachable (10.7.0.1:49152)

5. Checking Handshake with iOS Remote Services:
  ✅ [PASS] Apple Pair-Verify protocol handshake successful (PSK negotiated)
  ✅ [PASS] iPhone is unlocked, awake, and in Developer Mode

==================================================================
🎉 All checks passed. CDTK is ready!
```

---

## 📖 CLI Cheat Sheet

### 1. Battery Health & Power Telemetry (`cdtk-diag`)
```bash
cdtk-diag hw
```

### 2. App Lifecycle & Hardware Touch (`cdtk-ctrl`)
```bash
cdtk-ctrl procs --apps-only          # List running apps
cdtk-ctrl launch com.apple.Preferences # Launch Settings app
cdtk-ctrl tap 300 500                # Hardware touch tap at (300, 500)
cdtk-ctrl swipe 300 800 300 200      # Smooth swipe gesture
```

### 3. Sideloading & App Management (`cdtk-install`)
```bash
cdtk-install list                    # Enumerate installed third-party apps
cdtk-install install app.ipa -b com.example.demo -n "My App" # Sign & install
cdtk-install uninstall com.example.demo -y # Clean native uninstall
```

### 4. Configuration Profile Dispatch & Removal (`cdtk-profile`)
```bash
cdtk-profile list                    # List installed configuration profiles
cdtk-profile install cert.mobileconfig -y # Dispatch profile directly without Safari (confirm in Settings for personal devices)
cdtk-profile remove <PayloadIdentifier> -y # Remove profile silently without additional dialogs
```

### 5. Crash Log Extraction (`cdtk-crash`)
```bash
cdtk-crash list -n 10                # List 10 recent crash reports
cdtk-crash view <crash_file.ips>     # Structured analysis of crash stack trace
```

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
