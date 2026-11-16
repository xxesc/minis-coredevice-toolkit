# Troubleshooting

The main README lists symptoms only; this file holds the full reasoning and steps.

> Every "measured" note is a single observation on one device. There is no CI.

**Q1: `ConnectionRefusedError 10.7.0.1:49152` everywhere, or "connected but no answer"**

Two shapes, tell them apart by the symptom:

- `RST` / `ConnectionRefused`: nothing is listening on that port;
- TCP connects but 0 bytes come back: the loopback layer accepted it, `remoted` never answers. Surge below 5.23 silently
  drops `[IP Rewrite]` and looks exactly like this — check the Surge version and the three config lines first.

`coredevice_session` probes for the `RPPairing` magic to tell a live listener from a silent one, and tries
`CDTK_RSD_PORT` → `/tmp/.cdtk_rsd_port.json` → 49152 → a scan of 49152–65535.

**Q2: Two cdtk commands at the same time — one of them "drops mid-way" or reads 0 bytes**

`remoted` has a rule with no exceptions (iOS 27.x behaviour, documented in `pymobiledevice3`'s
`remote/remotexpc.py`): **replacement by source address** — an incoming connection whose source IP matches an existing
peer cancels that peer's connection before any handshake is read. Over a single-device loopback reflect every process
shares that address, so only one RSD session can be live at a time:

- the newcomer evicts the earlier one → the earlier one reports `ConnectionRefused`, drops mid-way, or `0 bytes read`;
- port scanning (thousands of connections) replaces peers over and over and will almost certainly kill another session.

**A cross-process lock is built in**: `CoreDeviceSession` holds `/tmp/.cdtk_session.lock` (`flock`) for the whole tunnel,
so the later command prints "another cdtk session is using the device, queueing…" and runs serially. `cdtk-doctor`
steps 4–6 (scan + real handshake + tunnel) hold the same lock. The queue wait defaults to 120 s and then fails with
`another cdtk session has held the device for more than 120s`.

| Variable            | Effect                                          |
| ------------------- | ----------------------------------------------- |
| `CDTK_LOCK_TIMEOUT` | Queue wait in seconds, default 120, `0` = wait forever |
| `CDTK_LOCK_FILE`    | Lock path, default `/tmp/.cdtk_session.lock`    |
| `CDTK_NO_LOCK=1`    | Disable the lock (only when you serialise yourself) |

Real parallelism needs a **different loopback source address per session** (one reflect rule each); process isolation
alone cannot provide it.

**Q3: The loopback is fine (RPPairing answers) but there is still no listener**

`remoted` closed it (dual-identity re-attach / lock-screen suspend / an evicted concurrent session). Unlocking, rebooting
or reconnecting the proxy does not restore it; replugging USB once does. First rule out Q2: `pgrep -f cdtk-` for leftover
processes — `cdtk-doctor` sweeps session dirs older than a day whose pid is gone.

**Q4: Handshake identity**

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

**Q5: `cdtk-ctrl launch` on the host app's own bundle id kills it**

The host app is the one running this toolchain. `cdtk-ctrl launch` defaults to `kill_existing=True`
(`launch_application(bundle_id, kill_existing=not args.no_kill)`), so it terminates the target's existing instance before
starting a new one. Launching the host therefore kills it: the UI reports an interruption, the log shows a PID change
with no shutdown sequence, and there is no matching `.ips`.

That is a deliberate termination, not a side effect of a protocol clash. `--no-kill` sends
`terminateExisting: false`, so the system sees the running instance and just foregrounds it. PID values from four
consecutive `launch` calls on one device (target `com.anthropic.claude`, deliberately not the host):

| call | PID |
| ---- | --- |
| `launch` (default) | 10129 |
| `launch` (default, again) | **10130** ← new process |
| `launch --no-kill` | 10130 |
| `launch --no-kill` (again) | **10130** ← unchanged |

**Rule**: launch other apps normally. Switch back to the host with
`cdtk-ctrl launch <host bundle id> --no-kill` (activate only), or tap its icon. Add `--no-notify` to suppress the banner.

**Keep this apart from Q2.** Same symptom area, different cause:

| | trigger | what happens | fix |
| --- | --- | --- | --- |
| this entry | `launch` without `--no-kill` | the host is **terminated** and restarted; PID changes, UI says interrupted | add `--no-kill` |
| Q2 | two cdtk commands running **at once** | the later one kills the earlier one's session: `ConnectionRefused` / `0 bytes read` | serialize (cross-process lock is built in) |

With `--no-kill` the way back is safe: the process is not restarted, so a shell command in flight and the session
context both survive. What can end a running command is iOS's background suspension, not `launch`.

**Q6: Does the tunnel keep resources after a command finishes**

No. Each command is its own process; the RSD session and the Node child are released on exit (single observation: no
leftover process and no listening port one second after exit). A clean exit leaves nothing behind; a session interrupted by `timeout` or SIGKILL leaves a directory containing `relay.sock`,
and `cdtk-doctor` sweeps those older than a day whose pid is gone (`--no-sweep` skips the sweep). `/tmp/.cdtk_rsd_port.json` (the port cache) is kept by design.

---
