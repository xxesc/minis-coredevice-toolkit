# Surge Loopback Setup

**English | [中文](SURGE_LOOPBACK_zh.md)**

For `cdtk-*` to reach CoreDevice RSD from the phone itself, `10.7.0.1` has to be reflected back to the device.
This is the only setup verified by this repository.

---

## Configuration

Three lines in the Surge config — two under `[General]`, one under `[IP Rewrite]`:

```ini
[General]
tun-included-routes = 10.7.0.1/32
always-raw-tcp-keywords = "Content-Type: application/pairing+tlv8"

[IP Rewrite]
10.7.0.1 = reflect
```

Or import the module in [`surge/local-loopback.sgmodule`](../surge/local-loopback.sgmodule):

```ini
#!name=CoreDevice RSD Local Loopback
#!desc=Reflect 10.7.0.1 back to the device for CDTK

[General]
tun-included-routes = %APPEND% 10.7.0.1/32
always-raw-tcp-keywords = %APPEND% "Content-Type: application/pairing+tlv8"

[IP Rewrite]
10.7.0.1 = reflect
```

What each line does:

| Setting                                   | Purpose                                                                                                            |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `tun-included-routes = 10.7.0.1/32`       | iOS defaults to `skip-proxy = 10.0.0.0/8`, which bypasses the TUN; this single-host route pulls `10.7.0.1` back in |
| `10.7.0.1 = reflect`                      | Reflects connections to that address back to the phone                                                             |
| `always-raw-tcp-keywords = …pairing+tlv8` | The pairing handshake is binary TLV; keep Surge from trying to decrypt it                                          |

The scope is that one `/32`; LAN and internet traffic are untouched.

---

## Verify

```bash
cdtk-doctor
```

Step 4 connects to the port and step 5 performs a real Pair-Verify handshake. Only step 5 passing means it works.

`nc -zv 10.7.0.1 49152` only proves the port is reachable, not that `remoted` answers.

---

## Notes

- Surge below 5.23 silently drops `[IP Rewrite]`: every port connects instantly and not a single byte arrives.
- The phone must be on Wi-Fi; 49152 is closed over cellular.
- Only one VPN can be active at a time.
