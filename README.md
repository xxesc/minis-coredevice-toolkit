# CDTK — CoreDevice ToolKit

**Drive iOS CoreDevice (RSD) services from a shell on the iPhone itself: install IPAs, inject touches, read containers, read crash logs, manage profiles, read battery data.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Host: Minis / iSH](https://img.shields.io/badge/Host-Minis%20%2F%20iSH-green.svg)]()

**English | [中文](README_zh.md)**

---

## What this is

Command-line tools that run inside Minis (iSH / Alpine Linux) and reach iOS CoreDevice RSD services through a Surge
loopback plus a TLS-PSK relay — so installing an IPA, injecting touches, reading a container or reading battery data
becomes one command instead of "plug in a computer" or "jailbreak".

**Scope**

- Not a jailbreak: no root, no system partitions. Only the services RSD exposes.
- Needs Surge ≥ 5.23 to reflect `10.7.0.1` back to the phone — see the [loopback guide](references/SURGE_LOOPBACK.md).
- Needs a RemotePairing record — see the [pairing guide](references/PAIRING_GUIDE.md).
- The first run needs one USB connection so `remoted` advertises the listener; the pairing record itself can be
  obtained on-device.
- Tested on iPhone 14 (iPhone14,7) / iOS 27.3, host Minis 1.16. Other versions are not verified.
  There is no CI; every "measured" note is a single observation.

## How it works

`cdtk-*` reads the key from the pairing record → starts a Node.js TLS-PSK relay → connects to `10.7.0.1:<rsd_port>`
over the `pmd-pytcp` userspace stack → RSD handshake for the service table → RemoteXPC calls → tunnel torn down on exit.

```text
Minis (iSH)                   loopback                    iOS kernel
cdtk-* ── coredevice_session ──► 10.7.0.1:49xxx ──► remoted ──► RSD services
        └ Node TLS-PSK relay + pytcp userspace stack
```

## Prerequisites

1. An iOS device with Developer Mode on;
2. Minis as the host (iSH / Alpine Linux, aarch64);
3. Surge ≥ 5.23 with `10.7.0.1` reflected locally — see the [loopback guide](references/SURGE_LOOPBACK.md);
4. A pairing record at `/root/.cdtk/pairing/` (0600) — see the [pairing guide](references/PAIRING_GUIDE.md);
5. A computer, needed only to re-plug USB when the listener drops.

## Install

```bash
git clone https://github.com/xxesc/minis-coredevice-toolkit.git
cd minis-coredevice-toolkit/src
sh setup.sh
```

`setup.sh` installs the dependencies (`pymobiledevice3` with `--no-deps`, skipping the `sslpsk-pmd3` build) and puts the
commands in `/usr/local/bin`.

Then run the doctor:

```bash
cdtk-doctor          # --zh for Chinese output
```

It runs six checks: runtimes, Python modules, the pairing file and its permissions, the loopback port, the Pair-Verify
handshake, and finally a real `createListener` tunnel. Only the sixth proves the tunnel works — Pair-Verify alone just
validates the host signature. The device identifier is masked by default; `--show-udid` prints it in full.
