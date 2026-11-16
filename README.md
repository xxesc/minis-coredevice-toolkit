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

## Tools

| Command            | Purpose                  |
| ------------------ | ------------------------ |
| `cdtk-doctor`      | Environment checks, sweep stale session dirs |
| `cdtk-install`     | List apps, install / uninstall IPAs |
| `cdtk-ctrl`        | Processes, launch apps, touch |
| `cdtk-ui`          | Read the UI: element tree, OCR targeting, tap by text |
| `cdtk-notify`      | System banners (Minis only) |
| `cdtk-profile`     | Profiles: list / install / remove |
| `cdtk-fs`          | Read containers and media |
| `cdtk-diag`        | Battery data, kernel logs |
| `cdtk-crash`       | List, fetch and parse `.ips` |
| `cdtk-inspect`     | WebKit pages, JS injection |
| `cdtk-springboard` | Home screen layout backup / apply |
| `cdtk-proc`        | Jetsam exemptions, signals |

`-h` works on almost everything; `cdtk-doctor -h` starts the checks instead, and `cdtk-notify` prints usage when run
bare. `cdtk-install` prefers `zsign` and falls back to `rcodesign` (unpack → swap profile → re-sign per entitlements →
repack).

## Common commands

```bash
cdtk-diag hw                                # battery health
cdtk-ctrl procs --apps-only                 # running apps
cdtk-ctrl launch com.example.demo           # launch an app
cdtk-ctrl tap 585 642                       # pixel coordinates, native portrait
cdtk-install install app.ipa -y             # install (-y required)
cdtk-install info com.example.demo          # signing identity, container, App Groups
cdtk-install install app.ipa -y -s -b com.example.demo2 -n "Demo2"   # new bundle id needs -s
cdtk-crash list -n 10
cdtk-profile list
```

Destructive commands (`install` / `uninstall` / `profile install|remove` / `proc signal`) refuse to run without `-y`;
`springboard apply` turns interactive without it. `com.example.demo` is a placeholder.

## Reading and driving the UI (cdtk-ui)

`cdtk-ctrl` can only tap coordinates; it has no idea what is on screen. `cdtk-ui` adds that layer:
screenshot + OCR → text to coordinates → tap → report whether the screen changed and whether it settled.

```bash
cdtk-ui tree --app minis                # focusable elements (accessibility labels)
cdtk-ui press "Send"                     # tap by text; reports changed / percent / settled
cdtk-ui press "some old message" --scroll 4   # not on screen? scroll and search
cdtk-ui press --at 1042,173              # icon-only buttons: coordinates only
cdtk-ui grid                             # screenshot with a labelled coordinate grid
cdtk-ui paste "text with spaces" --allow  # clipboard path, the reliable one
cdtk-ui input "abc"                      # plain ASCII token; read back and verified
```

**Targeting is OCR-first.** The element tree is scroll-dependent and incomplete (SwiftUI virtualises); OCR only sees
the visible area, which is exactly the question that matters.

**Always pass `--app`.** The audit daemon remembers the last target process, so after switching apps a plain `tree`
returns the *previous* app's elements with no error at all. Matching prefers `*.app/<same-named executable>` and skips
`.appex` / `PlugIns` — Safari alone has `MobileSafari` plus `SafariWebExtension`.

Limits:

- **Icon-only buttons** (back, more options, copy, send) have no text, so measure with `grid` and use `press --at`.
- **`input` auto-routes to the clipboard.** Any text containing a space or non-ASCII goes straight to paste.
  Keyboard input gets rewritten by the IME — pinyin eats the space as "confirm candidate" (`minis skills` →
  `minisskills`) and converts valid-pinyin letters to Han characters; a third-party IME's English QWERTY mode
  swallowed the space too. `--no-paste` forces the keyboard.
- **A third-party IME may intercept `Cmd+V` as well.** Measured with Doubao IME: the pasted text landed in its
  own clipboard strip and the field stayed empty. `paste` now reads the screen back and fails loudly instead of
  claiming success; switch to the system keyboard when that happens.
- **`input --submit` may not submit** — Return is swallowed the same way. Use `press "Go"` instead.
- Element coordinates are not exposed (`Frame` / `AXFrame` return `None`), so tapping must go through coordinates.
  Apps that keep content in a WebContent process (Safari) have a near-empty tree — use OCR.

## Troubleshooting

| Symptom | Go to |
| --- | --- |
| `ConnectionRefusedError 10.7.0.1:49152`, or connects but no bytes come back | Q1 loopback or listener |
| Two commands at once, one drops mid-way / reports `0 bytes read` | Q2 concurrent sessions (lock exists) |
| RPPairing answers but still no listener | Q3 re-plug USB once |
| Listener disappears after the handshake identity changes | Q4 `CDTK_HOST_UUID` |
| The host app is killed after being brought back to the foreground | Q5, below |
| Leftover resources after a command finishes | Q6 none, released on exit |

**Q5 in one line:** `cdtk-ctrl launch` defaults to `kill_existing=True` — it **terminates before launching**, so
launching the host app kills itself. Use `--no-kill` to switch back to the host (it passes `terminateExisting: false`).
This is not Q2: Q5 is a deliberate termination, Q2 is two concurrent commands where the later one evicts the earlier.

Full reasoning, environment-variable tables and the PID comparison live in
[Troubleshooting](references/TROUBLESHOOTING.md).

## Security

- **Pairing record**: searched in `CDTK_PAIRING_FILE` → `/root/.cdtk/pairing/` (0600) → `/var/minis/workspace/cdtk/`.
  The last one is shared by every Minis session — permissions are on you; prefer the first two.
- **Never commit a pairing record**: the `*.plist` holds the device signing key.
- **PSK goes over stdin**, never argv; temp dirs are `mkdtemp` + `0700` and removed on clean exit.
- **Routing**: only one `10.7.0.1/32` host route is added.

## Packaging as a skill

No `SKILL.md` is shipped (that is each host's own format); `SKILL.example.md` is the template:

```bash
mkdir -p <skills>/coredevice-toolkit/scripts
cp -r src/* <skills>/coredevice-toolkit/scripts/
cp SKILL.example.md <skills>/coredevice-toolkit/SKILL.md     # edit name / description / triggers
sh <skills>/coredevice-toolkit/scripts/setup.sh
cdtk-doctor
```

Three things an assistant cannot do alone: enable Developer Mode, configure the Surge loopback, export a pairing
record. Without them `cdtk-doctor` fails at steps 3–6.

## Testing

After changing code or docs run `sh tests/smoke.sh` (touches no device, no network). It checks that every tool prints
usage, that every `--flag` mentioned in the docs exists in the corresponding script, and that the tools registered by
`setup.sh` match the tool table.

## License

[MIT](LICENSE)
