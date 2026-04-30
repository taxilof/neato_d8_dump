
# Neato D8 eMMC Layout

## Disk Overview

| Property | Value | Source |
|----------|-------|--------|
| Total size | 3.56 GB (7,471,071 sectors) | GPT header, LBA 1: `last_usable_lba = 7471070` |
| Sector size | 512 bytes | U-Boot `mmc read` / i.MX8MN standard |
| Partition table | GPT (EFI PART, rev 1.0) | GPT header at LBA 1, signature verified |
| Disk GUID | `ad39404d-f094-f444-b2ce-e4c74fc9ca6c` | GPT header field |
| Alternate GPT | LBA 7,471,103 (last sector) | GPT header `alternate_lba` field |
| First usable LBA | 34 | GPT header |
| Last usable LBA | 7,471,070 | GPT header |

**Source:** `emmc_blocks_0_2048.dd` (1 MB dump, blocks 0–2047) — GPT parsed from bytes 512–1023 (LBA 1) and partition entries at LBA 2–3.

---

## GPT Partition Table (5 partitions)

| # | Name | Type GUID | Start LBA | End LBA | Size | Byte Offset |
|---|------|-----------|-----------|---------|------|-------------|
| 1 | `kernel1` | `a2a0d0eb-e5b9-3344-87c0-68b6b72699c7` | 16,384 | 147,455 | 64 MB | 8 MB |
| 2 | `kernel2` | `a2a0d0eb-e5b9-3344-87c0-68b6b72699c7` | 147,456 | 278,527 | 64 MB | 72 MB |
| 3 | `rfs1` | `af3dc60f-8384-7247-8e79-3d69d8477de4` | 278,528 | 2,899,967 | 1.25 GB | 136 MB |
| 4 | `rfs2` | `af3dc60f-8384-7247-8e79-3d69d8477de4` | 2,899,968 | 5,521,407 | 1.25 GB | 1.38 GB |
| 5 | `user` | `af3dc60f-8384-7247-8e79-3d69d8477de4` | 5,521,408 | 7,471,069 | 952 MB | 2.63 GB |

**Source:** Partition entries at LBA 2–3 (offset 1024–1535 in dump). Type GUIDs parsed from bytes 0–15 of each 128-byte entry. Partition names decoded from UTF-16-LE at entry offset 56.

**Notes:**
- `kernel1` and `kernel2` share the same type GUID → both are kernel-type partitions (A/B boot).
- `rfs1`, `rfs2`, and `user` share a different type GUID → filesystem partitions.
- No dedicated "bootloader" partition exists in GPT. The bootloader lives in the hidden area between GPT and `kernel1`.

---

## Hidden Bootloader Area (LBA 34–16,383)

This ~8 MB region between the GPT partition entries (end at LBA 33) and the first partition (`kernel1` at LBA 16,384) is not listed in the GPT. It contains the full bootloader chain.

### Region Breakdown

| LBA Range | Byte Offset | Approx Size | Content | Evidence |
|-----------|-------------|-------------|---------|----------|
| 34–39 | 17 KB | 3 KB | Padding (all zeros) | Dump scan: 0 non-zero bytes |
| **40** | **20 KB (0x5000)** | 0.5 KB | **SPL entry point** | First instruction `d1002041` = `add x1, x8, #8` (ARM64). i.MX8MN ROM loads SPL from offset 0x5000 into eMMC (NXP boot ROM spec). Dump: 218/512 non-zero bytes |
| 44–89 | 22 KB–45 KB | ~32 KB | SPL code (ARM64 binary) | Continuous non-zero ARM64 instructions (`stp`, `ret`, function prologues). Dense block coverage |
| 90–96 | 45 KB–48 KB | ~3 KB | HAB/CSF strings | Strings: "IVT CSF", "Error: CSF header command not found", "hab entry function fail", "Secure boot fuse read error". NXP High Assurance Boot library compiled in |
| **91** | — | — | **U-Boot SPL version string** | `"U-Boot SPL 2020.04-1.7.0-2749_08020951_cfae4f98+gffc3fbe7e5 (Aug 02 2022 - 17:48:20 +0000)"` |
| 97–99 | 48 KB–50 KB | ~1.5 KB | IVT / DCD data | `540000000200000014000000` pattern (possible IVT header). Device Configuration Data for i.MX8MN |
| ~100–~330 | 50 KB–165 KB | ~115 KB | Sparse bootloader code | Mixed zero/non-zero blocks (71% non-zero in LBA 34–133, drops to 23% in 134–333) |
| **~300** | **~150 KB** | **~1 KB** | **DTB (Flattened Device Tree)** | Magic `d00dfeed`, version 17, total 1039 bytes. Contains FIT image strings ("description", "compression", "firmware", "loadables") — this is likely the SPL's FIT configuration, not the kernel DTB |
| 334–~1030 | 167 KB–515 KB | ~350 KB | **U-Boot proper (dense binary)** | 100% non-zero block density. Contains U-Boot core, MMC driver, fastboot, EFI boot manager, FDT library |
| **~755** | — | — | **U-Boot proper version** | `"U-Boot 2020.04-1.7.0-2749_08020951_cfae4f98+gffc3fbe7e5 (Aug 02 2022 - 17:48:20 +0000)"` — same build hash as SPL |
| 760–770 | — | — | **Boot environment defaults** | U-Boot env vars embedded in binary: `loadaddr`, `fdt_addr`, `bootcmd`, `mmcboot`, `reliable_boot`, etc. |
| ~906–~988 | — | ~40 KB | **Embedded device tree** | Strings: `fsl,imx8mn-gpio`, `fsl,imx8mn-sdma`, `fsl,imx8mn-ecspi`, `fsl,imx8mn-iomuxc`, `fsl,imx8mn-ddr4-som`, `mmc@30b40000`, `mmc@30b50000` |
| ~1030–2009 | — | ~480 KB | **Feature strings / CLI help** | U-Boot command help text (fdt commands, env commands, bootm help) |
| 2010–16383 | — | ~7 MB | Unknown (not in dump) | Dump only covers LBA 0–2047. Could be empty or contain additional data |

**Source:** All content boundaries derived from `emmc_blocks_0_2048.dd` (1 MB dump). Block density analysis, string extraction, and ARM64 disassembly of first instruction at LBA 40.

---

## A/B Reliable Boot Mechanism

U-Boot implements a reliable A/B boot scheme using environment variables:

### Boot Selection Logic (from `reliable_boot` env var, LBA ~768–770)

```
1. If recovery_status is set → warn, clear it, saveenv
2. boot_num = 0
3. If boot2_active != 1 AND boot1_valid == 1 → boot_num=1, root=/dev/mmcblk2p3
4. If boot2_active == 1 AND boot2_valid == 1 → boot_num=2, root=/dev/mmcblk2p4
5. If boot_num != 0 → run mmcboot (load + boot)
   else → run reliable_install (reset everything)
```

### Partition Mapping

| Boot Set | Kernel Partition | Root FS Partition | Root Device |
|----------|-----------------|-------------------|-------------|
| Set 1 | `kernel1` (mmcblk2p1) | `rfs1` (mmcblk2p3) | `/dev/mmcblk2p3` |
| Set 2 | `kernel2` (mmcblk2p2) | `rfs2` (mmcblk2p4) | `/dev/mmcblk2p4` |

Note: U-Boot uses `mmcdev=2` (eMMC is mmc2 on i.MX8MN), so `mmcblk2` = eMMC. The partition numbering (p1/p2 for kernels, p3/p4 for RFS) follows the GPT order.

### Recovery Logic (from `reliable_install`, LBA ~768)

On persistent boot failure: `upgrade_available=0`, `bootcount=0`, `boot1_valid=0`, `boot2_valid=0`, `boot2_active=0`, then set `boot1_valid=1`. Effectively resets to a clean Set 1 state.

**Source:** U-Boot env strings extracted from dump at LBA 760–770. Exact `reliable_boot` and `reliable_install` commands visible in plaintext.

---

## Encrypted Boot Chain

The kernel, device tree, initrd, and boot signature are **encrypted** on disk.

### Evidence (U-Boot env vars, LBA ~763–766)

- `fdt_file=emcraft-imx8mn-ddr4-som.dtb.enc` ← `.enc` suffix = encrypted
- `loadkeyblob` → loads a key blob file first
- `loadimage` → loads encrypted kernel, then calls `file_decrypt` before boot
- `loadfdt` → loads encrypted DTB, calls `file_decrypt`
- `loadinitrd` → loads encrypted initrd, calls `file_decrypt`
- `loadsig` → loads encrypted signature file, calls `file_decrypt`

### Boot Flow

```
1. fatload keyblob  → RAM
2. fatload image.enc → RAM
3. file_decrypt(keyblob, image.enc) → plaintext kernel at loadaddr (0x40480000)
4. fatload dtb.enc → RAM
5. file_decrypt(keyblob, dtb.enc) → plaintext DTB at fdt_addr (0x43000000)
6. (optionally) load + decrypt initrd, sw-update key, signature
7. booti loadaddr initrd_addr fdt_addr
```

### Implications

- **Cannot extract kernel/DTB directly** from partition dumps — they're encrypted.
- **Need the key blob** (stored as a file on the FAT partition alongside kernel) to decrypt.
- The `file_decrypt` command is a custom U-Boot command (not standard), likely CAAM-accelerated (CAAM base at 0x30900000, Era 9).
- `fastboot getvar secure_boot=no` may only mean HAB signature verification is skipped, not that the filesystem contents are unencrypted.

**Source:** U-Boot env strings at LBA 763–766 in dump. `file_decrypt` command referenced in `loadimage`, `loadfdt`, `loadinitrd` env vars.

---

## Key U-Boot Environment Defaults (compiled into binary)

| Variable | Value | Source |
|----------|-------|--------|
| `loadaddr` | `0x40480000` | LBA 761 |
| `fdt_addr` | `0x43000000` | LBA 762 |
| `fdt_high` | `0xffffffffffffffff` | LBA 762 |
| `fdt_file` | `emcraft-imx8mn-ddr4-som.dtb.enc` | LBA 762 |
| `mmcdev` | `2` (eMMC) | LBA 759 (`/dev/mmcblk%dp2`) |
| `mmcroot` | `/dev/mmcblk1p2 rootwait rw` (default, overridden to p3/p4) | LBA 763 |
| `mmcargs` | `console=${console} quiet=quiet reset_cause=${reset_cause} platform=${platform}` | LBA 763 |
| `bootcmd` | `mmc dev ${mmcdev}; if mmc rescan; then run reliable_boot; ...` | LBA 760–761 |
| `script` | `boot.scr` | LBA 762 |
| `jh_mmcboot` | `mw 0x303d0518 0xff; ...` (Jailhouse / SoC fuses?) | LBA 762 |

**Source:** Plaintext strings extracted from `emmc_blocks_0_2048.dd`, LBA 760–770.

---

## Visual Layout Map

```
LBA:     0         34    40         300   334      760  906     1030    16384    147456    278528    2899968   5521408   7471071
         |         |     |          |     |        |    |        |        |         |         |         |         |         |
Byte:    0       17K   20K       150K   167K     380K  456K    515K     8MB      72MB     136MB    1.38GB   2.63GB   3.56GB
         |         |     |          |     |        |    |        |        |         |         |         |         |         |
         [MBR][GPT Header][GPT Entries][Pad ][SPL ][..SPL+HAB..][DTB_fit][U-Boot proper (dense)][Embedded DTB][CLI Help][...unknown...]
                                                                                          [  kernel1  ][  kernel2  ][  rfs1        ][  rfs2        ][  user        ]
```

---

## Dump Files Available

| File | LBA Range | Size | Date | Notes |
|------|-----------|------|------|-------|
| `emmc_blocks_0_2048.dd` | 0–2047 | 1.0 MB | 2026-04-27 | First 1 MB, bootloader only |
| `emmc-dump-all/emmc_dump_all_0_4.dd` | 0–3 (partial) | 2.0 KB | 2026-04-26 | — |
| `emmc-dump-all/emmc_dump_all_0_5.dd` | 0–4 (partial) | 2.5 KB | 2026-04-26 | — |
| `2026-04-28_emmc_dump_lba_0_50000_115200_minicorrupted.dd` | 0–49,999 | 25.6 MB | 2026-04-28 | First 50k: MBR + GPT + full bootloader + first 17.6 MB of kernel1 |
| `2026-04-30_emmc_dump_lba_50000_50000_115200_minicorrupted.dd` | 50,000–99,999 | 25.6 MB | 2026-04-30 | Second 50k: kernel1 mid-to-late (all high-entropy encrypted data) |

**Coverage:** LBA 0–99,999 (48.8 MB / 3.56 GB total = 1.3%). Covers MBR, GPT, full hidden bootloader area (LBA 0–16383), and kernel1 partition from start through ~LBA 100,000 (out of 147,455 end LBA).

---

## Extended Bootloader Area (LBA 2000–16383) — from 50k-block dump

The 50k-block dump (LBA 0–49,999) covers the entire hidden bootloader area. New findings beyond the original 1 MB dump:

### Block Density Map (LBA 0–16383)

```
LBA      0-  1999:  39.1% non-zero  (SPL + early U-Boot)
LBA   2000-  3999:   0.5% non-zero  (almost all zeros — gap)
LBA   4000-  5999:  90.4% non-zero  (U-Boot proper)
LBA   6000-11999: 100.0% non-zero  (U-Boot proper, dense)
LBA  12000-13999:  45.7% non-zero  (sparse tail)
LBA  14000-15999:  80.0% non-zero  (ATF/OP-TEE?)
LBA  16000-16383: 100.0% non-zero  (padding to kernel1)
```

### Key Findings

| LBA Range | Size | Content | Notes |
|-----------|------|---------|-------|
| 0–1999 | ~1 MB | SPL + early U-Boot | Matches original 1 MB dump analysis |
| 2000–3999 | ~1 MB | **Near-empty gap** | Only 10 non-zero blocks. Likely unused/reserved space |
| 4000–11999 | ~4 MB | **U-Boot proper (dense)** | 100% non-zero. Core binary, drivers, commands |
| 12000–13999 | ~1 MB | **Sparse U-Boot tail** | 45% non-zero. Possibly debug info or padding |
| 14000–15999 | ~1 MB | **Dense continuation** | 80% non-zero. Likely ATF, OP-TEE, or additional firmware |
| 16000–16383 | ~192 KB | **Padding to partition boundary** | 100% non-zero up to kernel1 start |

**Entropy:** Bootloader dense regions ~6.4 bits/byte (typical compressed ARM64). The gap (LBA 2000–3999) is essentially zeros.

### New Strings Found

- FAT32 detection code
- U-Boot partition type checking (`Invalid partition type`)
- Android boot image support strings
- Recovery DTB handling
- uImage format handling

Confirms U-Boot has Android boot image and uImage support, plus FAT32 filesystem handling.

---

## kernel1 Partition Contents (LBA 16384–147,455) — from 50k-block dumps

### Overview

Combined dumps cover kernel1 from LBA 16,384 to LBA 99,999 (offset 0–42.9 MB within the 64 MB partition).

**Not a raw filesystem.** No FAT boot sector (no `EB 3C 90` / `E9` jump), no ext4 superblock (magic `0xEF53` not at offset +1024). The partition contains **encrypted binary data** as expected from U-Boot env analysis (`.enc` suffixes, `file_decrypt` command).

### Entropy Analysis

| Region (LBA) | Entropy (bits/byte) | Interpretation |
|---------------|---------------------|----------------|
| 16384–22000 | ~7.96–7.99 | **Highly encrypted/compressed** data |
| 24000–25400 | ~2.8–4.0 | **Low entropy** — FIT images (DTBs) + repeating fill pattern |
| 25400–49999 | ~7.5–8.0 | **Encrypted/compressed** data |
| 50000–99999 (2nd dump) | ~7.99–8.0 | **Uniform high entropy** — fully encrypted throughout |

### FIT Images Found Inside kernel1

Despite encryption, **three unencrypted Flattened Device Tree (FDT) blobs** were found:

| LBA | Offset | Size | Model String | Notes |
|-----|--------|------|--------------|-------|
| 24,803 | 0xC1C600 | 36,301 bytes (71 blocks) | `Neato i.MX8MNano DDR4 Lego board` | Near `NEATO-~2ENC` string — boot config FIT or key structure |
| 24,852 | 0xC22800 | 38,167 bytes (75 blocks) | `Neato i.MX8MNano DDR4 Prime board` | Contains `fsl,imx8mn` compat strings, board description |
| 34,672 | 0x10EE000 | 1,039 bytes (2 blocks) | — | **SPL FIT config** — matches bootloader area one. Contains `Configuration to load ATF before U-Boot`, `uboot@1`, `U-Boot (64-bit)`. Likely a backup/stub FIT header |

The two larger DTBs (LBA 24,803 and 24,852) are **unencrypted device trees** embedded within the encrypted kernel image container. They appear to be **fallback DTBs** (Lego vs Prime board variants) or unencrypted metadata within a FIT image that wraps encrypted blobs.

### Anomalous Regions

#### Repeating 16-byte Fill Pattern (LBA ~24,900–25,300)

- **Pattern:** `1999d4ab 34e61fc7 5a681df0 8e005b25` (repeating every 16 bytes)
- **Extent:** ~411 consecutive 512-byte blocks (210 KB)
- **Entropy:** 4.0 bits/byte (exactly 16 unique bytes)
- **Interpretation:** Likely **encrypted padding/alignment filler** within a FIT image container. Not UART corruption (would show random noise, not a stable repeating pattern).

#### Sparse/Zero Region (LBA ~32,000–33,999)

- **1,142 all-zero blocks** + **856 non-zero blocks** (2 blocks with only `0x20` space chars)
- **Interpretation:** Boundary between two separate images/containers within kernel1, or unused/erased sectors.

### UART Corruption Assessment ("minicorrupted")

- **First 50k (LBA 0–49,999):** Minimal. Known structures (MBR, GPT, U-Boot strings, FDT magic) intact and parseable. Anomalous regions are real data, not corruption.
- **Second 50k (LBA 50,000–99,999):** All blocks non-zero, ~8.0 bits/byte. Since data is encrypted, corruption is **undetectable** without reference.
- **Verdict:** Unencrypted structures (bootloader, DTBs) show no corruption signs. Encrypted regions cannot be verified. Dumps are **approximately correct but not bit-perfect**.

### Updated Visual Layout Map

```
LBA:     0       2000  4000      8000  12000 14000 16000 16384 24803 24900 25400 32000 34672 50000        100000  147456
         |        |     |         |      |      |      |      |      |      |      |      |      |      |            |       |
Byte:    0       1MB   2MB      4MB   6MB  7MB  7.5MB  8MB  12.1MB 12.2MB 12.3MB 15.6MB 16.9MB 24.4MB      48.8MB   72MB
         |        |     |         |      |      |      |      |      |      |      |      |      |      |            |       |
         [SPL+U-Boot][gap][   U-Boot proper    ][spars][fill][pad][  kernel1 (encrypted)     ][DTBs][fill][zeros][FIT][ encrypted  ]
         [               Hidden Bootloader Area (~8 MB)                ][          kernel1 partition (64 MB)                                ]
```

---

## Open Questions

1. **What exactly is in LBA 4000–11999?** Likely U-Boot proper, ATF, and OP-TEE. Disassembly needed.
2. **Key blob format** — where stored on disk? Same partition as kernel? What algorithm does `file_decrypt` use?
3. **Why are DTBs unencrypted inside kernel1?** The two large DTBs at LBA 24,803 and 24,852 are plaintext. Fallback DTBs or unencrypted FIT metadata?
4. **The `user` partition** — what filesystem? ext4? Neato maps, logs, firmware updates?
5. **Boot failure analysis** — which partition is the device failing to boot from? Corrupted kernel, damaged encrypted data, or broken U-Boot?
6. **Repeating fill pattern** at LBA 24,900–25,300 — encrypted zeros? FIT padding mode?
