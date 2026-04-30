# Neato D8 eMMC Layout

## Disk Overview

| Property | Value (dec) | Value (hex) | Source |
|----------|-------------|-------------|--------|
| Total size | 3.56 GB (7,471,071 usable sectors) | 0x71FFDE sectors | GPT header `last_usable_lba` |
| Sector size | 512 bytes | 0x200 bytes | U-Boot `mmc read` / i.MX8MN standard |
| Partition table | GPT (EFI PART, rev 1.0) | — | GPT header at LBA 0x1, signature verified |
| Disk GUID | `ad39404d-f094-f444-b2ce-e4c74fc9ca6c` | — | GPT header field |
| Alternate GPT | LBA 7,471,103 | LBA 0x71FFFF | GPT header `alternate_lba` field |
| First usable LBA | 34 | 0x22 | GPT header |
| Last usable LBA | 7,471,070 | 0x71FFDE | GPT header |

**Source:** `emmc_blocks_0_2048.dd` (1 MB dump, blocks 0–2047) — GPT parsed from bytes 512–1023 (LBA 1) and partition entries at LBA 2–3.

---

## GPT Partition Table (5 partitions)

| # | Name | Type GUID | Start LBA (dec) | Start LBA (hex) | End LBA (dec) | End LBA (hex) | Size | Byte Offset |
|---|------|-----------|----------------|-----------------|---------------|---------------|------|-------------|
| 1 | `kernel1` | `a2a0d0eb-e5b9-3344-87c0-68b6b72699c7` | 16,384 | 0x4000 | 147,455 | 0x23FFF | 64 MB | 8 MB |
| 2 | `kernel2` | `a2a0d0eb-e5b9-3344-87c0-68b6b72699c7` | 147,456 | 0x24000 | 278,527 | 0x43FFF | 64 MB | 72 MB |
| 3 | `rfs1` | `af3dc60f-8384-7247-8e79-3d69d8477de4` | 278,528 | 0x44000 | 2,899,967 | 0x2C3FFF | 1.25 GB | 136 MB |
| 4 | `rfs2` | `af3dc60f-8384-7247-8e79-3d69d8477de4` | 2,899,968 | 0x2C4000 | 5,521,407 | 0x543FFF | 1.25 GB | 1.38 GB |
| 5 | `user` | `af3dc60f-8384-7247-8e79-3d69d8477de4` | 5,521,408 | 0x544000 | 7,471,069 | 0x71FFFD | 952 MB | 2.63 GB |

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
| Set 1 | `kernel1` (mmcblk2p1) LBA 0x4000 | `rfs1` (mmcblk2p3) LBA 0x44000 | `/dev/mmcblk2p3` |
| Set 2 | `kernel2` (mmcblk2p2) LBA 0x24000 | `rfs2` (mmcblk2p4) LBA 0x2C4000 | `/dev/mmcblk2p4` |

Note: U-Boot uses `mmcdev=2` (eMMC is mmc2 on i.MX8MN), so `mmcblk2` = eMMC. The partition numbering (p1/p2 for kernels, p3/p4 for RFS) follows the GPT order.

### Recovery Logic (from `reliable_install`, LBA ~768)

On persistent boot failure: `upgrade_available=0`, `bootcount=0`, `boot1_valid=0`, `boot2_valid=0`, `boot2_active=0`, then set `boot1_valid=1`. Effectively resets to a clean Set 1 state.

**Source:** U-Boot env strings extracted from dump at LBA 760–770. Exact `reliable_boot` and `reliable_install` commands visible in plaintext.

---

## Verified Hidden Bootloader Area (LBA 0x0–0x897) — `dump_valid/` (2026-04-30)

> **Source:** `dump_valid/2026-04-30_emmc_lba_0_2200_try1.dd` (2,200 blocks, verified hex `mmc read`)

### Block Density Map

```
LBA  0x000- 0x063 (0-99):     37.0% non-zero  (MBR + GPT + early ROM/SPL)
LBA  0x064- 0x1F3 (100-499):  49.8% non-zero  (mixed)
LBA  0x1F4- 0x3E7 (500-999):  43.8% non-zero  (mixed)
LBA  0x3E8- 0x5DB (1000-1499):100.0% non-zero  (dense code)
LBA  0x5DC- 0x7CF (1500-1999):100.0% non-zero  (dense code)
LBA  0x7D0- 0x897 (2000-2199):100.0% non-zero  (U-Boot env + code)
```

### Entropy

| Region (LBA) | Entropy (bits/byte) | Interpretation |
|---------------|---------------------|----------------|
| 0–0x63 | 2.72 | MBR, GPT, padding, sparse SPL |
| 0x64–0x1F3 | 5.89 | Mixed code/data |
| 0x1F4–0x3E7 | 0.00 | All zeros (large gap) |
| 0x3E8–0x5DB | 6.39 | Dense ARM64 code |
| 0x5DC–0x7CF | 6.34 | Dense ARM64 code |
| 0x7D0–0x897 | 5.28 | U-Boot env strings + code |

### Verified Layout (LBA 0–2199)

| LBA (hex) | LBA (dec) | Content | Evidence |
|-----------|-----------|---------|----------|
| 0x0 | 0 | **Protective MBR** | Valid 0xAA55 signature | 
| 0x1 | 1 | **GPT Header** | "EFI PART" rev 1.0, 92-byte header |
| 0x2–0x3 | 2–3 | **GPT Partition Entries** | 5 partitions parsed correctly |
| 0x22–0x3F | 34–63 | **Zeros (padding)** | All-zero blocks |
| 0x22–0x3F | 34–63 | Zeros (padding) | All-zero blocks |
| **0x40** | **64** | **SPL (IVT entry point)** | First ARM64 instruction `d1002041` (`add x1,x8,#8`). Located at byte offset 0x8000 in user area. The eMMC boot partition's FCB points the ROM to this offset. 218 non-zero bytes in this block |
| 0x41–0x63 | 65–99 | Sparse SPL code | Mixed zero/non-zero blocks |
| 0x64–0x1F3 | 100–499 | Mixed code/data | 50% non-zero density |
| 0x1F4–0x3E7 | 500–999 | **Large zero gap** | 0.00 entropy — completely empty |
| 0x3E8–0x7CF | 1000–1999 | **Dense ARM64 code** | 100% non-zero, 6.3+ bits/byte entropy | 
| 0x7D0–0x897 | 2000–2199 | **U-Boot env + dense code** | 100% non-zero, env vars + strings |

### SPL Location

SPL (IVT + first instruction) is at **byte offset 0x8000 in the user area** (LBA 0x40). This is set by the FCB in the eMMC boot partition (hardware partition 1/2), which `mmc read` cannot access. The ROM reads the FCB from the boot partition, which points to user area byte offset 0x8000. The standard i.MX8MN default is 0x4000 — Neato uses a custom 0x8000 offset.

### U-Boot Environment Variables (verified at LBA 0x761–0x768)

| Variable | Value | LBA (hex) |
|----------|-------|-----------|
| `baudrate` | `115200` | 0x761 |
| `loadaddr` | `0x40480000` | 0x761 |
| `console` | `${console},${baudrate} rdinit=/linuxrc clk_ignore_unused` | 0x761 |
| `console` | `ttymxc1,115200` | 0x762 |
| `fdt_addr` | `0x43000000` | 0x762 |
| `fdt_file` | `emcraft-imx8mn-ddr4-som.dtb.enc` | 0x762 |
| `mmcdev` | `2` (eMMC) | 0x763 |
| `mmcroot` | `/dev/mmcblk1p2 rootwait rw` | 0x763 |
| `upgrade_available` | `1` | 0x768 |
| `bootcount` | `0` (default) | 0x768 |

### Encrypted Boot Chain (verified)

- `neato-prime.dtb.enc`, `neato-frost.dtb.enc` at LBA 0x758
- `loadkeyblob` → loads key blob from FAT partition
- `loadimage` → loads encrypted kernel → `file_decrypt`
- `loadfdt` → loads encrypted DTB → `file_decrypt`
- `loadinitrd` → loads encrypted initrd → `file_decrypt`
- `loadsig` → loads encrypted signature → `file_decrypt`
- `file_decrypt` function found at LBA 0x7D1

### U-Boot Version Strings (verified)

- **SPL:** `U-Boot SPL 2020.04-1.7.0-2749_08020951_cfae4f98+gffc3fbe7e5 (Aug 02 2022 - 17:48:20 +0000)`
- **U-Boot proper:** `U-Boot 2020.04-1.7.0-2749_08020951_cfae4f98+gffc3fbe7e5 (Aug 02 2022 - 17:48:20 +0000)`
- **board_name:** `DDR4 SOM`
- **HAB:** `hab fuse not enabled`

### A/B Reliable Boot (verified at LBA 0x768)

`reliable_boot` env var: checks `boot2_active`, `boot1_valid`, `boot2_valid` to select slot 1 (kernel1/rfs1) or slot 2 (kernel2/rfs2). On bootcount expiry → `altbootcmd` → swap partition and rollback.

### SPL Strings (verified)

- DDR4 init: `DDRINFO: start DRAM init`, `DDRINFO: DRAM rate %dMTS`, `ddrphy calibration done`
- HAB: `hab fuse not enabled`, `spl: ERROR: image authentication fail`
- Boot devices: `Normal Boot`, `BOOTROM`, `usbd`, `mmcsd`, `FAT32`
- FIT: `Can't found uboot FIT image in 640K range`

---

## ⚠️ STALE — Bootloader Area Beyond LBA 2199

> **Source:** Old dumps (blocks 0-2048, 0-10240) — used decimal LBA numbers which U-Boot interpreted as hex for blocks ≥10.
> **The actual LBA mapping for these dumps is unknown/scrambled. Do not trust LBA values below.**
> Byte offsets within blocks may still be correct, but the block-to-LBA mapping is wrong.

### STALE: Hidden Bootloader Area (LBA 34–16,383) — from old dumps

| LBA Range | Size | Content | Status |
|-----------|------|---------|--------|
| 0–1999 | ~1 MB | SPL + early U-Boot | ⚠️ LBA values unverified |
| 2000–3999 | ~1 MB | Near-empty gap | ⚠️ LBA values unverified |
| 4000–11999 | ~4 MB | U-Boot proper (dense) | ⚠️ LBA values unverified |
| 12000–13999 | ~1 MB | Sparse U-Boot tail | ⚠️ LBA values unverified |
| 14000–15999 | ~1 MB | Dense continuation | ⚠️ LBA values unverified |
| 16000–16383 | ~192 KB | Padding to kernel1 | ⚠️ LBA values unverified |

### STALE: kernel1 Partition Contents

> From old dumps with scrambled LBA mapping. The following LBA values are unreliable.

- ~~DTBs at LBA 24,803 and 24,852~~ — LBA values are wrong, actual positions unknown
- ~~Repeating fill pattern at LBA ~24,900–25,300~~ — same
- ~~Sparse/zero region at LBA ~32,000–33,999~~ — same

### STALE: DTB Extractions

- `DTB_lego_lba_24803.dtb` / `.dts` — **LBA in filename is wrong**. File contains a valid DTB but at unknown actual LBA.
- `DTB_prime_lba_24852.dtb` / `.dts` — **LBA in filename is wrong**. Same issue.

---

## Dump Files

| File | LBA Range | Verified? | Size | Date | Notes |
|------|-----------|-----------|------|------|-------|
| `dump_valid/2026-04-30_emmc_lba_0_2200_try1.dd` | 0x0–0x897 | ✅ Yes | 1.1 MB | 2026-04-30 | Verified hex `mmc read`, 0 errors |
| `dumps/DTB_lego_lba_24803.dtb` | unknown | ❌ LBA wrong | 24 KB | 2026-04-30 | Valid DTB, actual LBA unknown |
| `dumps/DTB_prime_lba_24852.dtb` | unknown | ❌ LBA wrong | 26 KB | 2026-04-30 | Valid DTB, actual LBA unknown |
| `dumps/2026-04-28_emmc_dump_lba_0_50000_115200_minicorupted.dd` | scrambled | ❌ | 25.6 MB | 2026-04-28 | Hex/decimal bug, blocks ≥10 at wrong LBA |
| `dumps/2026-04-30_emmc_dump_lba_50000_50000_115200_minicorupted.dd` | scrambled | ❌ | 25.6 MB | 2026-04-30 | Hex/decimal bug |
| `emmc_blocks_0_2048.dd` | scrambled | ❌ | 1.0 MB | 2026-04-27 | Blocks ≥10 at wrong LBA |

---

## Open Questions

1. **SPL at LBA 0x40 (64) vs expected LBA 0x28 (40)** — ROM loads from offset 0x5000 = LBA 0x28, but verified dump shows zeros there and code at LBA 0x40. Why the 24-block (12 KB) gap? Custom ROM config? Different eMMC boot config?
2. **What's in LBA 100–499?** Mixed density, needs investigation.
3. **Large zero gap at LBA 500–999 (0x1F4–0x3E7)** — 500 blocks of pure zeros between mixed bootloader areas. Purpose unknown.
4. **Key blob format** — `file_decrypt` algorithm, CAAM-accelerated?
5. **`bootlimit` not found** — U-Boot compiled-in default (likely 3). `bootcount` was observed climbing to 95+ across dump sessions, suggesting the device was stuck in a boot loop.
6. **The `user` partition** — what filesystem? Needs fresh dump to verify.
7. **Boot failure root cause** — encrypted data damaged, key blob missing, or hardware fault?

---

## `mmc read` Addressability & Hex Warning

### ⚠️ CRITICAL: Always Use Hex LBA Addresses

U-Boot's `mmc read` is inconsistent with decimal vs hex. **Always use `0x` prefix for LBA addresses** to avoid ambiguity.

```
# AMBIGUOUS — may read wrong LBA depending on U-Boot build:
uuu FB: ucmd mmc read 0x42000000 5521408 1

# SAFE — explicitly hex:
uuu FB: ucmd mmc read 0x42000000 0x544000 1
```

Convert: `printf '0x%x\n' 5521408` → `0x544000`

### Measured Read Limit

- **Last readable LBA:** 0x71FFF0 (7,470,480 decimal)
- **First failing LBA:** 0x720000 (7,471,104 decimal)
- **Full eMMC readable** — all partitions accessible

| Region | Start LBA (hex) | End LBA (hex) | Accessible? |
|--------|-----------------|---------------|-------------|
| Bootloader (hidden) | 0x0 | 0x3FFF | ✅ |
| kernel1 | 0x4000 | 0x23FFF | ✅ |
| kernel2 | 0x24000 | 0x43FFF | ✅ |
| rfs1 | 0x44000 | 0x2C3FFF | ✅ |
| rfs2 | 0x2C4000 | 0x543FFF | ✅ |
| user | 0x544000 | 0x71FFFD | ✅ |
| Alt GPT | 0x71FFFF | 0x71FFFF | ✅ |
