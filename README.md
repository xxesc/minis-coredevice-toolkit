# CDTK — CoreDevice ToolKit

**Drive iOS CoreDevice (RSD) services from the command line on the phone itself: install apps, inject touches, read app containers, inspect crash logs, manage profiles, read battery data.**

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
- Needs Surge ≥ 5.23 to reflect `10.7.0.1` back to the phone.
- Needs a RemotePairing record — see the [pairing guide](references/PAIRING_GUIDE.md).
- The first run needs one USB connection (from a computer or any USB host) so `remoted` advertises the listener; the pairing record itself can be obtained on-device (see the pairing guide). Recovery after the listener closes is Q2.
- Tested on iPhone 14 (iPhone14,7) / iOS 27.3, host Minis 1.16. Other versions are not verified by this repo.
  There is no CI and no reproducible test script; every "measured" note below is a single observation.

---

## How it works

`cdtk-*` starts → reads the key from the pairing record → spawns a Node.js TLS-PSK relay → connects to
`10.7.0.1:<rsd_port>` over the `pmd-pytcp` userspace stack → RSD handshake for the service map → talks to one service
over RemoteXPC → the tunnel is torn down when the command exits.

```text
Minis (iSH)                   loopback                    iOS kernel
cdtk-* ── coredevice_session ──► 10.7.0.1:49xxx ──► remoted ──► RSD services
        └ Node TLS-PSK relay + pytcp userspace stack
```

---

## Prerequisites

1. An iOS device with Developer Mode enabled;
2. Host Minis (iSH / Alpine Linux, aarch64);
3. Surge ≥ 5.23 configured as in the [loopback guide](references/SURGE_LOOPBACK.md);
4. A pairing record at `/root/.cdtk/pairing/` (0600) — see the [pairing guide](references/PAIRING_GUIDE.md);
5. A computer (only for the USB replug in Q2).

---

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
validates the host signature. Failures come with the command to fix them. The device identifier is masked by default;
`--show-udid` prints it in full.

---

## Tools

| Command            | Does                         |
| ------------------ | ---------------------------- |
| `cdtk-doctor`      | Env audit, sweep old dirs    |
| `cdtk-install`     | List / install / remove apps |
| `cdtk-ctrl`        | Processes, launch, touch     |
| `cdtk-notify`      | System banners (Minis only)  |
| `cdtk-profile`     | Profiles: list / add / del   |
| `cdtk-fs`          | App container, media         |
| `cdtk-diag`        | Battery data, kernel log     |
| `cdtk-crash`       | List / parse `.ips`          |
| `cdtk-inspect`     | WebKit pages, inject JS      |
| `cdtk-springboard` | Home layout backup / apply   |
| `cdtk-proc`        | Jetsam immunity, signals     |

`-h` works on almost every command; `cdtk-doctor -h` starts the audit instead of printing help, and `cdtk-notify` shows usage when run without arguments.

`cdtk-install` signs with `zsign` when it is available. If not, it falls back to `rcodesign`: unpack the IPA, replace
`embedded.mobileprovision`, sign the bundle with the profile's entitlements, and repack. Passwords may be passed as
`密码：xxx` — the prefix is stripped automatically.

---

## Common commands

```bash
cdtk-diag hw                                # battery health
cdtk-ctrl procs --apps-only                 # running apps
cdtk-ctrl launch com.example.demo           # launch an app
cdtk-ctrl tap 585 642                       # pixel coordinates, native portrait, same as a screenshot
cdtk-ctrl swipe 585 1800 585 600
cdtk-install list
cdtk-install info com.example.demo          # signer, container path, App Groups
cdtk-install install app.ipa -y             # -y is required
cdtk-install install app.ipa -y -s -b com.example.demo2 -n "Demo2"   # -b/-n need -s
cdtk-crash list -n 10
cdtk-crash view <file.ips>
cdtk-profile list
```

Commands that need confirmation: `install`, `uninstall`, `profile install/remove`, `proc signal` refuse without `-y`;
`springboard apply` falls back to an interactive prompt without it.
Every value in these examples is a placeholder: `com.example.demo` only shows the format and has nothing to do with any real
app. The `Pairing identifier` line printed by `cdtk-doctor` is the pairing record's `identifier` (a UUID), masked by
default — it is not the device UDID.
Known limit: `-b` / `-n` only apply when the IPA is actually re-signed; on an already-signed IPA without `-s` they are
silently ignored.

---

## Troubleshooting

**Q1: `ConnectionRefusedError 10.7.0.1:49152` everywhere, or "connected but no answer"**

Two shapes, tell them apart by the symptom:

- `RST` / `ConnectionRefused`: nothing is listening on that port;
- TCP connects but 0 bytes come back: the loopback layer accepted it, `remoted` never answers. Surge below 5.23 silently
  drops `[IP Rewrite]` and looks exactly like this — check the Surge version and the three config lines first.

`coredevice_session` probes for the `RPPairing` magic to tell a live listener from a silent one, and tries
`CDTK_RSD_PORT` → `/tmp/.cdtk_rsd_port.json` → 49152 → a scan of 49152–65535.

**Q2: The loopback is fine (RPPairing answers) but there is still no listener**

`remoted` closed it (dual-identity re-attach / lock-screen suspend). Unlocking, rebooting or reconnecting the proxy does
not restore it; replugging USB once does.

**Q3: Handshake identity**

`remoted` remembers each peer's handshake UUID; a different UUID means re-attach, which closes every listener that peer
advertised. This toolchain sends the pairing record's `identifier` in both pair-verify and the RSD handshake;
`CDTK_HOST_UUID` overrides it, `CDTK_DEBUG=1` prints what is used.

| Variable              | Effect                      |
| --------------------- | --------------------------- |
| `CDTK_RSD_PORT`       | Pin control port, no scan   |
| `CDTK_RSD_SCAN=0`     | Disable scanning            |
| `CDTK_RSD_SCAN_RANGE` | Narrow the scan             |
| `CDTK_HOST_UUID`      | Override handshake identity |
| `CDTK_DEBUG=1`        | Debug output                |

**Q4: `cdtk-ctrl launch` on the host app's own bundle id kills it**

The host app is the one running this toolchain. `cdtk-ctrl launch` defaults to `kill_existing=True`
(`launch_application(bundle_id, kill_existing=not args.no_kill)`), so it terminates the target's existing instance before
starting a new one. Launching the host therefore kills it: the UI reports an interruption, the log shows a PID change
with no shutdown sequence, and there is no matching `.ips`.

**Rule**: launch other apps normally. Switch back to the host with
`cdtk-ctrl launch <host bundle id> --no-kill` (activate only), or tap its icon. Add `--no-notify` to suppress the banner.

**Q5: Does the tunnel keep resources after a command finishes**

No. Each command is its own process; the RSD session and the Node child are released on exit (single observation: no
leftover process and no listening port one second after exit). A clean exit leaves nothing behind; a session interrupted by `timeout` or SIGKILL leaves a directory containing `relay.sock`,
and `cdtk-doctor` sweeps those older than a day whose pid is gone (`--no-sweep` skips the sweep). `/tmp/.cdtk_rsd_port.json` (the port cache) is kept by design.

---

## Security

- **Pairing record**: looked up via `CDTK_PAIRING_FILE` → `/root/.cdtk/pairing/` (0600) → `/var/minis/workspace/cdtk/`.
  The last one is shared by every session inside Minis — use it at your own risk; prefer the first two.
- **Never commit a pairing record**: the `.plist` holds the device signing key; keep it out of repositories and
  public shares.
- **PSK**: handed to the Node child over stdin, never on a command line.
- **Temp dirs**: `mkdtemp` + `0700` per session; removed on a clean exit, left behind if the process is killed.
- **Routes**: adds one host route, `10.7.0.1/32`, to capture that loopback address; other routing rules are untouched.

---

## Packaging as a skill

There is no `SKILL.md` in this repo (each host has its own skill format), but there is a template. Three steps:

1. Create the directory and copy the scripts in (the directory name does not matter; `setup.sh` locates its
   files relative to itself):

   ```bash
   mkdir -p <skills>/coredevice-toolkit/scripts
   cp -r src/* <skills>/coredevice-toolkit/scripts/
   ```

2. Turn the template into `SKILL.md` and adjust `name` / `description` / triggers:

   ```bash
   cp SKILL.example.md <skills>/coredevice-toolkit/SKILL.md
   ```

3. Install and self-check:

   ```bash
   sh <skills>/coredevice-toolkit/scripts/setup.sh
   cdtk-doctor
   ```

Three things an assistant cannot do alone and a human has to provide: Developer Mode, a working Surge loopback, and a
pairing record (StikPair or wloc). Without them, steps 3–6 of `cdtk-doctor` will not pass.

## Testing

After touching code or docs, run:

```bash
sh tests/smoke.sh
```

It checks three things: every tool prints usage, every `--flag` mentioned in the READMEs exists in the matching script, and the tool list in `setup.sh` matches the tool table. It does not touch the device or the network.

## License

[MIT](LICENSE)
