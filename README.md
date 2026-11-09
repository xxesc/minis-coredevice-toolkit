# CDTK — CoreDevice ToolKit

**Drive iOS CoreDevice (RSD) services from `cdtk-*` commands on the phone itself — no computer, no jailbreak.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Tested on iOS 27.3](https://img.shields.io/badge/Tested-iOS%2027.3-blue.svg)]()
[![Host: Minis / iSH](https://img.shields.io/badge/Host-Minis%20%2F%20iSH-green.svg)]()

**English | [中文](README_zh.md)**

---

## What this is

A set of command-line tools that run inside Minis (iSH / Alpine Linux) and reach iOS's CoreDevice RSD services
over a local loopback plus a TLS-PSK bridge — so that installing an IPA, injecting touches, reading an app
container, reading crash reports, managing configuration profiles or reading battery data become one command
instead of "plug in a computer" or "jailbreak".

**What it is not**

- Not a jailbreak: no root, no access to system partitions. Only the services RSD exposes.
- It needs Surge (or an equivalent) to reflect `10.7.0.1` back to the phone, and a RemotePairing record.
- Tested on iPhone 14 (iPhone14,7) / iOS 27.3, host Minis 1.16. Older iOS versions are not verified by this repo.
- Upstream APIs move: a `pymobiledevice3` upgrade can break a call. The tools probe capabilities where they can,
  but there is no guarantee.

---

## How it works

`cdtk-*` starts → reads the key from the pairing record → spawns a Node.js TLS-PSK relay → opens a tunnel to
`10.7.0.1:<rsd_port>` on the `pmd-pytcp` userspace stack → performs the RSD handshake to get the service map →
talks to one service over RemoteXPC (`installation_proxy`, `dtuhidd`, `house_arrest`, `crashreportcopymobile`, …)
→ the tunnel is torn down when the command exits.

```text
Minis (iSH)                   loopback                    iOS kernel
cdtk-* ── coredevice_session ──► 10.7.0.1:49xxx ──► remoted ──► RSD services
        └ Node TLS-PSK relay + pytcp userspace stack
```

---

## Prerequisites

1. An iOS device with Developer Mode enabled;
2. Host Minis (iSH / Alpine Linux, aarch64);
3. Surge ≥ 5.23 or an equivalent loopback setup with `10.7.0.1` reflected to the phone — see
   [Surge loopback guide](references/SURGE_LOOPBACK.md);
4. A RemotePairing-format pairing record in `~/.cdtk/pairing/` (0600) — see [pairing guide](references/PAIRING_GUIDE.md).

---

## Install

```bash
git clone https://github.com/xxesc/minis-coredevice-toolkit.git
cd minis-coredevice-toolkit/src
sh setup.sh
```

`setup.sh` installs the dependencies (`pymobiledevice3` with `--no-deps`, skipping the `sslpsk-pmd3` build) and puts
the commands in `/usr/local/bin`. Then run the doctor:

```bash
cdtk-doctor
```

It checks the Node/Python runtimes, the Python modules, the pairing file and its permissions, the loopback port and
one real RSD handshake, and prints the command to fix whatever fails.

---

## Tools

| Command            | Service                  | Does                                          |
| ------------------ | ------------------------ | --------------------------------------------- |
| `cdtk-doctor`      | self-check               | Environment audit, sweeps old session dirs    |
| `cdtk-install`     | `installation_proxy`     | List apps, install an IPA, uninstall          |
| `cdtk-ctrl`        | `dtuhidd` / `appservice` | List processes, launch apps, inject touches   |
| `cdtk-notify`      | `apple-notification`     | System banner around app launches             |
| `cdtk-profile`     | `MCInstall`              | List / install / remove profiles              |
| `cdtk-fs`          | `house_arrest`           | Read an app container and the media partition |
| `cdtk-diag`        | `diagnostics_relay`      | Battery data, kernel log                      |
| `cdtk-crash`       | `crashreportcopymobile`  | List and parse `.ips`                         |
| `cdtk-inspect`     | `webinspector`           | List WebKit pages, inject JS                  |
| `cdtk-springboard` | `springboard.iconstate`  | Back up / apply the home layout               |
| `cdtk-proc`        | `processcontrol`         | Jetsam immunity, signals                      |

---

## Common commands

```bash
cdtk-diag hw                              # battery health
cdtk-ctrl procs --apps-only               # running apps
cdtk-ctrl launch com.apple.Preferences    # launch Settings
cdtk-ctrl tap 585 642                     # pixel coordinates, native portrait, same as a screenshot
cdtk-ctrl swipe 585 1800 585 600
cdtk-install list
cdtk-install install app.ipa -b com.example.demo -n "Demo"
cdtk-crash list -n 10
cdtk-crash view <file.ips>
cdtk-profile list
```

Every command supports `-h`.

---

## Troubleshooting

**Q1: `ConnectionRefusedError 10.7.0.1:49152` everywhere, or "connected but no answer"**

Two failure modes, and TCP reachability does not tell them apart:

| Symptom                     | Meaning                                                 |
| --------------------------- | ------------------------------------------------------- |
| `RST` / `ConnectionRefused` | Nothing is listening on that port any more              |
| TCP connects, 0 bytes back  | The loopback layer accepted it, `remoted` never answers |

`coredevice_session` probes for the `RPPairing` magic to tell a live listener from a silent one, and tries
`CDTK_RSD_PORT` → the `/tmp/.cdtk_rsd_port.json` cache → 49152 → a scan of 49152–65535.

**Q2: The full scan finds no listener**

`remoted` closed its listener (dual-identity re-attach / lock-screen suspend). The reliable recovery is
**replugging USB once**; unlocking, rebooting or reconnecting the proxy does not help.

**Q3: Handshake identity**

`remoted` remembers the handshake UUID of every peer; a different UUID means re-attach, which closes every service
listener that peer had advertised. This toolchain sends the pairing record's `identifier` in both pair-verify and the
RSD handshake; `CDTK_HOST_UUID` overrides it and `CDTK_DEBUG=1` prints what is actually used.

| Variable                          | Effect                                     |
| --------------------------------- | ------------------------------------------ |
| `CDTK_RSD_PORT`                   | Pin the control port (no scanning)         |
| `CDTK_RSD_SCAN=0`                 | Disable scanning                           |
| `CDTK_RSD_SCAN_RANGE=49152-50000` | Narrow the scan                            |
| `CDTK_HOST_UUID`                  | Override the RSD handshake identity        |
| `CDTK_DEBUG=1`                    | Print the handshake UUID and other details |

**Q4: `cdtk-ctrl launch` on the host app's own bundle id gets the process killed**

The host app is the one running this toolchain. Launching it through `cdtk-ctrl launch` makes the process receive
`SIGKILL` the moment it returns to the foreground: the UI reports an interruption, the log shows a PID change with no
shutdown sequence, and there is no matching `.ips` in the system crash store (only the app's own
`FOREGROUND CRASH (SIGKILL — app was in use)` marker).

Measured, one PID across all four combinations:

| Switch away        | Switch back                                                                          | Result |
| ------------------ | ------------------------------------------------------------------------------------ | ------ |
| `cdtk-ctrl launch` | `cdtk-ctrl launch <host>`                                                            | killed |
| `cdtk-ctrl launch` | tap the icon                                                                         | fine   |
| `cdtk-ctrl launch` | any SpringBoard-normal launch (iCTRL `launch_app`, Swipt `device.launchApplication`) | fine   |
| any other channel  | any                                                                                  | fine   |

It goes through the DVT / AppService RSD service, and using it on the host itself triggers the termination.
Launching any other app with it is unaffected. **Rule**: switch away however you like; switch back through a normal
launch path.

**Q5: Does the tunnel keep resources after a command finishes**

No. Every `cdtk-*` call is its own process; the RSD session and the Node relay child are released on exit (measured:
no leftover process and no listening port one second after exit). What stays is `/tmp/.cdtk_rsd_port.json` (the port
cache, reused by design) and an empty `/tmp/cdtk_*` session directory containing a 0-byte `relay.sock`. Only sessions
killed by `timeout` leave the directory behind; `cdtk-doctor` sweeps those older than a day.

---

## Security

- **Pairing key**: read only from `~/.cdtk/pairing/` (0600); a world-readable copy is moved into a private directory
  and locked down first.
- **PSK**: handed to the Node child over stdin, never on a command line.
- **Temp dirs**: `mkdtemp` + `0700` per session, cleaned on exit.
- **Scope**: one route, `10.7.0.1/32`. No LAN or internet traffic is captured.

---

## License

[MIT](LICENSE)
