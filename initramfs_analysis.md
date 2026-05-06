# Neato D8 Initramfs Analysis

**Date:** 2026-05-06
**Source:** `/home/fox/workspace/projects/2026-04-neato-d8/fox2/ex/`
**Files:** 1888
**OS:** NXP i.MX Release Distro 5.4-zeus (Yocto Zeus)
**Init:** systemd (symlinked: `/init -> /lib/systemd/systemd`)
**Architecture:** ARM64 (aarch64), i.MX8M Nano (imx8mnlego-ddr4)

---

## 1. Overview

The initramfs is a minimal Yocto-based root filesystem labeled "Lego Startup Initrd". Its sole purpose is to unlock the encrypted root partition on the eMMC and boot the system. It contains no graphical interface — only the tools necessary for the boot process and basic system maintenance.

---

## 2. System Identity

| Field | Value |
|-------|-------|
| **Hostname** | `imx8mnlego-ddr4` |
| **OS** | NXP i.MX Release Distro 5.4-zeus (zeus) |
| **Initrd Name** | Lego Startup Initrd v0.1 |
| **Build Date** | 2022-10-06 10:17:37 |
| **Machine-ID** | (empty) |
| **Kernel** | i.MX8M Nano (imx8mn), DDR4 variant |
| **Board** | Neato D8 (based on NXP i.MX8M Nano "Lego" board) |

---

## 3. Root Login & Authentication

### 3.1 Password Hashes

**Root password:** `*` (locked, no password login possible)
**Shadow entry:** `root:*:19271:0:99999:7:::`

The `*` in the shadow file means the root account is locked. No password-based login for root. All other accounts (daemon, bin, sys, etc.) also have `*` or `!` — all locked.

**Conclusion:** Root login via password is **not possible**. This is the Yocto default configuration.

### 3.2 PAM Configuration

The PAM configuration is the **Yocto default** with no Neato-specific customizations:

- **common-auth:** `pam_unix.so nullok_secure` — standard Unix auth, allows empty passwords
- **common-account:** `pam_unix.so` — standard
- **common-password:** `pam_unix.so sha512` — SHA512 password hashing
- **common-session:** `pam_unix.so` + `pam_systemd.so`
- **login:** standard Shadow login with `pam_securetty.so`, `pam_nologin.so`, `pam_limits.so`, `pam_lastlog.so`, `pam_motd.so`, `pam_mail.so`
- **su:** `pam_rootok.so` (root can su without password), `pam_env.so`, `pam_mail.so`
- **other:** everything denied (`pam_deny.so`) — secure fallback

**No Neato-specific PAM modules or rules found.**

### 3.3 Securetty

Comprehensive securetty configuration covering many ARM SoC serial ports:
- Standard: `console`, `ttyS0-ttyS3`, `tty1-tty63`, `pts/0-3`
- ARM AMBA: `ttyAM0-ttyAM3`, `ttyAMA0-ttyAMA3`
- i.MX: `ttymxc0-ttymxc5` (important: ttymxc1 = UART2 for debug)
- USB: `ttyUSB0-ttyUSB2`, `ttyGS0`
- Hypervisor: `hvc0`, `xvc0`
- QCOM: `ttyHSL0-ttyHSL3`, `ttyMSM0-ttyMSM2`
- Samsung: `ttySAC0-ttySAC3`
- TI OMAP: `ttyO0-ttyO3`
- Xilinx: `ttyPS0-ttyPS1`
- Freescale lpuart: `ttyLP0-ttyLP5`

**Root login is permitted on all these terminals** (as long as PAM doesn't block it).

### 3.4 Login-Defs

- **ENCRYPT_METHOD:** SHA512
- **PASS_MAX_DAYS:** 99999
- **PASS_MIN_DAYS:** 0
- **UMASK:** 022
- **LOGIN_RETRIES:** 5
- **LOGIN_TIMEOUT:** 60
- **CREATE_HOME:** yes
- **DEFAULT_HOME:** yes
- **SYSLOG_SU_ENAB:** yes
- **SYSLOG_SG_ENAB:** yes

**No Neato-specific customizations.**

---

## 4. Network Configuration

### 4.1 NTP (timesyncd.conf)

```ini
[Time]
NTP=time1.google.com time2.google.com time3.google.com time4.google.com ntp.aliyun.com
```

**Neato-specific:** Uses Google NTP servers and Alibaba Cloud (aliyun.com). This is an i.MX/Yocto-typical configuration.

### 4.2 DHCP (udhcpc)

Busybox udhcpc with standard script (`/etc/udhcpc.d/50default`):
- Supports both `ip` and `ifconfig` (fallback)
- Configures IP, subnet, gateway, DNS
- Uses `resolvconf` when available

### 4.3 DNS/NSS

```ini
hosts: files myhostname dns
```

Uses `libnss-myhostname2` for local hostname resolution.

### 4.4 Logind

```ini
HandlePowerKey=ignore
```

**i.MX-specific:** Power key is ignored (no automatic shutdown when pressing the power button in initramfs).

---

## 5. Neato-Specific Components

### 5.1 unlock-rootfs.sh — Encrypted Root Partition

**Path:** `/usr/sbin/unlock-rootfs.sh`
**This is the most important Neato-specific component of the initramfs.**

**Source:**

```sh
#!/bin/sh

if [ `fw_printenv boot2_active  2> /dev/null` = "boot2_active=1" ]; then
    boot_part="/dev/mmcblk2p2"
    root_part="/dev/mmcblk2p4"
else
    boot_part="/dev/mmcblk2p1"
    root_part="/dev/mmcblk2p3"
fi

mount $boot_part /mnt

# if the key is created by kernel 4.14, convert it to newer format
if grep -q ":hex:" /mnt/fs_key_blob.enc; then
    echo -ne "\x4f\x67\x61\x54\x00\x00\x00\x00\x01\x00\x00\x00\x10\x00\x00\x00\x4c\x00\x00\x00" > /tmp/fs_key_4_14.bin
    for ((i=5;i<133;i+=2)); do
        dd if=/mnt/fs_key_blob.enc bs=1 skip=$i count=2 status=none | xargs -INN echo -en "\xNN" >> /tmp/fs_key_4_14.bin
    done
    echo -ne "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" >> /tmp/fs_key_4_14.bin
    caam-keygen import /tmp/fs_key_4_14.bin randomkey
    mv /tmp/fs_key_4_14.bin /mnt/fs_key_blob.enc
fi

caam-keygen import /mnt/fs_key_blob.enc randomkey

cat /data/caam/randomkey | keyctl padd logon logkey: @s
umount /mnt
dmsetup -v create encrypted --table "0 $(blockdev --getsz $root_part) crypt capi:tk(cbc(aes))-plain :36:logon:logkey: 0 $root_part 0 1 sector_size:512"
```

#### Line-by-Line Explanation

**`#!/bin/sh`** — Runs with POSIX sh, not bash. The shell in the initramfs is busybox sh.

**Lines 3–9: Determine which partition set to use (A/B scheme)**

```sh
if [ `fw_printenv boot2_active 2> /dev/null` = "boot2_active=1" ]; then
```

`fw_printenv boot2_active` reads a U-Boot environment variable. The output is either `boot2_active=1` or empty/0. The `2> /dev/null` suppresses errors if the variable is not set or `fw_printenv` is unavailable — in that case the else branch is taken.

| `boot2_active` | Boot partition | Root partition |
|---|---|---|
| 1 | mmcblk2p2 | mmcblk2p4 |
| 0 (or unset) | mmcblk2p1 | mmcblk2p3 |

This is the A/B update scheme. If an OTA update fails, the device can fall back to the other partition set.

**Line 11: Mount the boot partition**

```sh
mount $boot_part /mnt
```

Mounts the boot partition (e.g. mmcblk2p1) to `/mnt`. The key file `fs_key_blob.enc` lives on this partition.

**Lines 13–22: Convert old key format (kernel 4.14 to new binary format)**

```sh
if grep -q ":hex:" /mnt/fs_key_blob.enc; then
```

Checks if the key blob is in the old hex-string format (created with kernel 4.14). The old format stores the key as a hex string with `:hex:` as a marker prefix.

```sh
echo -ne "\x4f\x67\x61\x54\x00\x00\x00\x00\x01\x00\x00\x00\x10\x00\x00\x00\x4c\x00\x00\x00" > /tmp/fs_key_4_14.bin
```

Writes a 20-byte binary header to a new temporary file:
- `\x4f\x67\x61\x54` = magic "Ogat" (internal name)
- `\x00\x00\x00\x00` = padding/reserved
- `\x01\x00\x00\x00` = version (1, little-endian 32-bit)
- `\x10\x00\x00\x00` = flags (0x10)
- `\x4c\x00\x00\x00` = total blob length (76 bytes)

```sh
for ((i=5;i<133;i+=2)); do
    dd if=/mnt/fs_key_blob.enc bs=1 skip=$i count=2 status=none | xargs -INN echo -en "\xNN" >> /tmp/fs_key_4_14.bin
done
```

Conversion loop. The old hex format looks like `:hex:a1b2c3d4...`. The loop:
- Starts at byte 5 (skipping the `:hex:` prefix, which is 5 bytes)
- Reads 2 bytes at a time (one hex pair = one binary byte)
- Converts each hex pair to a binary byte
- Appends it to the new binary file
- Goes up to byte 132 (64 hex pairs = 32 bytes of key data)

```sh
echo -ne "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" >> /tmp/fs_key_4_14.bin
```

Appends 12 null bytes as padding/end marker.

```sh
caam-keygen import /tmp/fs_key_4_14.bin randomkey
mv /tmp/fs_key_4_14.bin /mnt/fs_key_blob.enc
```

Imports the converted binary blob into the CAAM keyring, then **overwrites** the old hex format on the boot partition with the new binary format. This is a one-time migration — on the next boot the file is already in binary format and this if-branch is skipped.

**Line 24: Import the key blob**

```sh
caam-keygen import /mnt/fs_key_blob.enc randomkey
```

Imports the CAAM key blob (now in binary format) into the kernel keyring. The `caam-keygen` tool is NXP-specific and uses the i.MX8M Nano CAAM hardware module. The key is named "randomkey" — an arbitrary name used for later reference.

**Line 26: Load key into kernel keyring**

```sh
cat /data/caam/randomkey | keyctl padd logon logkey: @s
```

The critical step:
- `/data/caam/randomkey` — the CAAM module exposes the imported key here
- `cat` reads the raw key bytes
- `keyctl padd logon logkey: @s` — adds the key as type "logon" into the session keyring (`@s`) with the label "logkey:"

After this, the kernel holds the decryption key in memory.

**Line 27: Unmount boot partition**

```sh
umount /mnt
```

The boot partition is no longer needed. The key is now in the kernel keyring.

**Line 28: Create DM-Crypt device**

```sh
dmsetup -v create encrypted --table "0 $(blockdev --getsz $root_part) crypt capi:tk(cbc(aes))-plain :36:logon:logkey: 0 $root_part 0 1 sector_size:512"
```

The core command. Breaking down the DM-Crypt table:

| Field | Value | Meaning |
|---|---|---|
| Start | `0` | Start of virtual device |
| Length | `<sectors>` | Same size as root partition (dynamically determined via `blockdev --getsz`) |
| Target | `crypt` | Device-Mapper crypt target |
| Cipher | `capi:tk(cbc(aes))-plain` | CAAM token-based AES-CBC in plaintext mode |
| Key offset | `:36` | Key starts at byte 36 in the blob (after 20-byte header + 16 bytes IV/metadata) |
| Key type | `logon` | References the "logon" key from the kernel keyring |
| Key name | `logkey:` | The key's label in the keyring |
| IV offset | `0` | IV offset (0 = default) |
| Device | `<root_part>` | The real block device (e.g. mmcblk2p3) |
| Offset | `0` | Start offset on the device |
| Flags | `1` | DM-Crypt flag |
| Sector size | `512` | 512-byte sectors |

After this command, `/dev/mapper/encrypted` exists — a transparently decrypted view of the root partition. The system can now `switch_root` to the real root filesystem.

**Complete boot flow:**

```
1. Read U-Boot variable → A or B partition?
2. Mount boot partition
3. Convert key blob if old format
4. Import key blob into CAAM keyring
5. Load key from /data/caam/ into kernel keyring
6. Unmount boot partition
7. Create DM-Crypt device → /dev/mapper/encrypted
8. switch_root to real root filesystem
```

**Encryption:** AES-256-CBC via CAAM (Cryptographic Acceleration and Assurance Module)
**Key format:**
- New format: binary blob (magic "Ogat" + version + flags + key data + padding)
- Old format (kernel 4.14): hex string with `:hex:` prefix, gets converted automatically

**Key file location on eMMC:** `/home/fox/workspace/projects/2026-04-neato-d8/kernel/kernel1/fs_key_blob.enc` (96 bytes, extracted from kernel1 partition)

**A/B Partition Scheme:**
| | boot2_active=0 | boot2_active=1 |
|---|---|---|
| Boot (kernel) | mmcblk2p1 | mmcblk2p2 |
| Root (rfs) | mmcblk2p3 | mmcblk2p4 |

### 5.2 caam-keygen

**Path:** `/usr/bin/caam-keygen`
**Type:** ELF 64-bit ARM aarch64, stripped
**Purpose:** Imports CAAM key blobs into the kernel keyring
**Usage:** `caam-keygen import <file> <name>`
This is an NXP-specific tool for the i.MX8M Nano CAAM.

### 5.3 keyctl-caam

Installed as a standalone package (`keyctl-caam`). Likely needed for CAAM key management.

### 5.4 fw_printenv / fw_setenv

U-Boot environment tools (`libubootenv`). Used by `unlock-rootfs.sh` to read the `boot2_active` variable.

**fw_env.config:**
```
/dev/mmcblk2  0x400000  0x4000
```
U-Boot environment is stored on eMMC at offset 0x400000, size 0x4000.

### 5.5 firmware-imx-sdma

SDMA firmware loader script (`/etc/sdma`):
- Loads `sdma-imx6q.bin` or `sdma-imx7d.bin` via the Linux firmware SDMA interface
- Executed during the boot process

### 5.6 volatile-binds

Yocto package for volatile bind mounts. Creates temporary filesystems for volatile data.

### 5.7 touchscreen.rules

Udev rule for touchscreen detection:
```udev
SUBSYSTEM=="input", KERNEL=="event[0-9]*", ENV{ID_INPUT_TOUCHSCREEN}=="1", SYMLINK+="input/touchscreen0"
```
Creates a symlink `/dev/input/touchscreen0` for touchscreen devices.

---

## 6. Package List (opkg)

**Total:** ~130 packages (Yocto standard + Neato extensions)

### Categories:

**System Base:**
- `base-files`, `base-passwd`, `libc6`, `libgcc1`, `libstdc++6`

**Init/Systemd:**
- `systemd`, `systemd-initramfs`, `systemd-compat-units`, `systemd-conf`, `systemd-extra-utils`, `systemd-serialgetty`, `systemd-vconsole-setup`

**Shell/Tools:**
- `bash`, `busybox`, `coreutils`, `util-linux` (many sub-packages)

**Filesystem:**
- `e2fsprogs-e2fsck`, `e2fsprogs-mke2fs`, `lvm2`, `lvm2-scripts`, `lvm2-udevrules`, `thin-provisioning-tools`

**Network:**
- `busybox-udhcpc`

**Crypto/Security:**
- `keyutils`, `keyctl-caam`, `libcrypt2`, `pam-plugin-*` (many modules), `shadow`, `shadow-base`, `shadow-securetty`

**Hardware:**
- `firmware-imx-sdma`, `kbd`, `kbd-consolefonts`, `kbd-keymaps`, `kbenc`

**X11 (unexpected in initramfs):**
- `libx11-6`, `libxau6`, `libxcb1`, `libxdmcp6`

**Package Management:**
- `update-alternatives-opkg`, `update-rc.d`, `run-postinsts`

**Notable Neato Packages:**
- `keyctl-caam` — CAAM key management
- `libubootenv` — U-Boot environment access
- `volatile-binds` — volatile filesystem bindings

---

## 7. A/B Boot Scheme

The system uses an **A/B partition scheme** for redundant booting:

```
eMMC (mmcblk2):
  p1: Boot Partition A (kernel1, 64 MB)
  p2: Boot Partition B (kernel2, 64 MB)
  p3: Root Partition A (rfs1, 1280 MB, encrypted)
  p4: Root Partition B (rfs2, 1280 MB, encrypted)
  p5: User data partition (952 MB)
```

The U-Boot variable `boot2_active` controls which set is used. This enables safe OTA updates — one partition is updated while the other serves as fallback.

---

## 8. Encryption Architecture

```
+-------------------------------------------------------------+
| U-Boot                                                      |
|  - Reads boot2_active variable                              |
|  - Loads kernel + initramfs                                 |
+-------------------------------------------------------------+
                          |
                          v
+-------------------------------------------------------------+
| Initramfs (Lego Startup Initrd)                             |
|                                                             |
|  1. unlock-rootfs.sh:                                       |
|     a. fw_printenv boot2_active → determines partitions     |
|     b. Mount boot partition → /mnt                          |
|     c. caam-keygen import /mnt/fs_key_blob.enc randomkey    |
|     d. keyctl padd logon logkey: @s                         |
|     e. dmsetup create encrypted (AES-256-CBC via CAAM)      |
|                                                             |
|  2. Root partition is now available as /dev/mapper/encrypted|
|                                                             |
|  3. switch_root to real root filesystem                     |
+-------------------------------------------------------------+
                          |
                          v
+-------------------------------------------------------------+
| Root Filesystem (encrypted, on mmcblk2p3/p4)                |
+-------------------------------------------------------------+
```

**Key location:** `/mnt/fs_key_blob.enc` on the boot partition
**Encryption engine:** NXP CAAM (hardware acceleration)
**Algorithm:** AES-256-CBC
**DM-Crypt format:** `capi:tk(cbc(aes))-plain` (CAAM token-based)

---

## 9. Emcraft / NXP-Specific Customizations

The initramfs is based on the **NXP i.MX Yocto Project BSP** (Board Support Package), not directly on Emcraft. The "Lego" designation is the internal name for the i.MX8M Nano board.

**NXP-specific elements:**
- `HandlePowerKey=ignore` in logind.conf (i.MX-specific comment)
- `ttymxc0-ttymxc5` in securetty (i.MX UART controllers)
- CAAM-based encryption (NXP hardware crypto)
- SDMA firmware loader
- i.MX touchscreen rules in udev
- U-Boot environment on eMMC (offset 0x400000)

---

## 10. Security Analysis

### Strengths:
- Root account is locked (no password login)
- Root partition encryption via CAAM hardware
- PAM "other" fallback denies everything
- Securetty restricts root login to physical terminals
- A/B scheme enables safe OTA updates

### Weaknesses / Notes:
- `nullok_secure` in PAM allows empty passwords (Yocto default)
- No network services in initramfs (no SSH, no Telnet) — good
- No firewall rules (not relevant in initramfs)
- X11 libraries in initramfs (libX11, libxcb, etc.) — unusual, likely for later GUI use in the real root filesystem
- `DEFAULT_HOME=yes` in login.defs allows login without an existing home directory

---

## 11. Non-Default (Neato-Specific) Files

| File | Purpose |
|------|---------|
| `/usr/sbin/unlock-rootfs.sh` | Root partition decryption |
| `/usr/bin/caam-keygen` | CAAM key import |
| `/etc/fw_env.config` | U-Boot environment configuration |
| `/etc/sdma` | SDMA firmware loader |
| `/etc/udev/rules.d/touchscreen.rules` | Touchscreen detection |
| `/etc/initrd-release` | "Lego Startup Initrd" identity |
| `/etc/hostname` | "imx8mnlego-ddr4" |
| `/etc/issue` | "NXP i.MX Release Distro 5.4-zeus" |
| `/etc/securetty` | Extended with ARM SoC ports |
| `/etc/systemd/logind.conf` | `HandlePowerKey=ignore` |
| `/etc/systemd/timesyncd.conf` | Google + Aliyun NTP |

---

## 12. Summary

The initramfs is a **minimal, Yocto-based boot loader** with the following properties:

1. **No root login** — all accounts locked
2. **CAAM-based encryption** — AES-256-CBC via NXP hardware
3. **A/B partition scheme** — redundant booting with U-Boot control
4. **No network services** — purely local boot process
5. **NXP i.MX8M Nano specific** — CAAM, SDMA, i.MX UART, touchscreen
6. **No Emcraft-specific customizations** — pure NXP Yocto BSP
7. **X11 libraries present** — likely for later GUI use

The system is securely configured: no network access, no root login, encrypted root partition. The only attack vector would be physical access via the UART interface with a logged-in root account (but root is locked).
