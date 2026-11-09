# Pairing Record Guide

**English | [中文](PAIRING_GUIDE_zh.md)**

The RSD tunnel authenticates with a RemotePairing record (`.plist`) over SRP / TLS. Treat that file as a device credential.

---

## Format

`load_pairing()` accepts three top-level keys and skips any file missing one:

| Key           | Type   | Meaning                                         |
| ------------- | ------ | ----------------------------------------------- |
| `identifier`  | string | Pairing ID, also used as the RSD handshake UUID |
| `private_key` | data   | Ed25519 private key                             |
| `public_key`  | data   | Ed25519 public key                              |

Check a candidate file:

```bash
python3 -c "import plistlib;print(sorted(plistlib.load(open('pairing.plist','rb'))))"
```

---

## Getting one

What this repository has verified: enable Developer Mode on the phone, pair with **StikPair** on the device, then export
the pairing record (`.plist`) from StikPair. The exported file should contain the three keys above; put it in one of the
lookup paths below.

Other ways (for example generating it on a computer with `pymobiledevice3 remote pair`) are not verified here — try them
yourself if you need to.

> A `lockdown` record (`/var/db/lockdown/<UDID>.plist`) is not a pairing record: it carries
> `HostCertificate` / `HostPrivateKey` / `RootCertificate` and none of `identifier` / `private_key` / `public_key`.
> Putting it in the pairing folder does nothing.

---

## Where it is looked up

| Order | Location                                                           |
| ----- | ------------------------------------------------------------------ |
| 1     | CLI argument, e.g. `cdtk-install --pairing /path/to/pairing.plist` |
| 2     | Environment variable `CDTK_PAIRING_FILE`                           |
| 3     | `/root/.cdtk/pairing/*.plist`                                      |
| 4     | `/var/minis/workspace/cdtk/*.plist`                                |

The current working directory is **not** searched by default; set `CDTK_ALLOW_CWD_PAIRING=1` if you need that.

---

## Permissions

| State                      | Behaviour                                             |
| -------------------------- | ----------------------------------------------------- |
| `0600`                     | Used as is                                            |
| Too open (e.g. `0644`)     | Tightened to `0600` when `chmod` works                |
| Filesystem ignores `chmod` | Copied to `/root/.cdtk/pairing/` and locked to `0600` |

---

## Security

- The record holds the device's signing key; anyone with the file has developer-level debug access. Never commit it or
  upload it anywhere.
- CDTK never prints the private key or the PSK. `cdtk-install --password` does pass the **certificate** password (not the
  pairing key) to `zsign` on the command line, so it can show up in `ps` for a moment.
