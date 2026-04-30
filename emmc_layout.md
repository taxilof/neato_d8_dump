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

**Source:** `emmc_blocks_0_2048.dd` (1 MB dump, blocks 0–2047) — GPT parsed from bytes 512–1023 (LBA 1) and partition entries at LBA 2–3. Re-verified in `dump_valid/2026-04-30_emmc_lba_0_16384.dd`.

---

## GPT Partition Table (5 partitions)

| # | Name | Type GUID | Start LBA (dec) | Start LBA (hex) | End LBA (dec) | End LBA (hex) | Size | Byte Offset |
|---|------|-----------|----------------|-----------------|---------------|---------------|------|-------------|
| 1 | `kernel1` | `a2a0d0eb-e5b9-3344-87c0-68b6b72699c7` | 16,384 | 0x4000 | 147,455 | 0x23FFF | 64 MB | 8 MB |
| 2 | `kernel2` | `a2a0d0eb-e5b9-3344-87c0-68b6b72699c7` | 147,456 | 0x24000 | 278,527 | 0x43FFF | 64 MB | 72 MB |
| 3 | `rfs1` | `af3dc60f-8384-7247-8e79-3d69d8477de4` | 278,528 | 0x44000 | 2,899,967 | 0x2C3FFF | 1.25 GB | 136 MB |
| 4 | `rfs2` | `af3dc60f-8384-7247-8e79-3d69d8477de4` | 2,899,968 | 0x2C4000 | 5,521,407 | 0x543FFF | 1.25 GB | 1.38 GB |
| 5 | `user` | `af3dc60f-8384-7247-8e79-3d69d8477de4` | 5,521,408 | 0x544000 | 7,471,069 | 0x71FFFD | 952 MB | 2.63 GB |

**Source:** Partition entries at LBA 2–3 (offset 1024–1535 in dump). Type GUIDs parsed from bytes 0–15 of each 128-byte entry. Partition names decoded from UTF-16-LE at entry offset 56. Re-verified in `dump_valid/2026-04-30_emmc_lba_0_16384.dd`.

**Notes:**
- `kernel1` and `kernel2` share the same type GUID → both are kernel-type partitions (A/B boot).
- `rfs1`, `rfs2`, and `user` share a different type GUID → filesystem partitions.
- No dedicated "bootloader" partition exists in GPT. The bootloader lives in the hidden area between GPT and `kernel1`.

---

## Hidden Bootloader Area (LBA 0x0000–0x3FFF) — FULLY VERIFIED

> **Source:** `dump_valid/2026-04-30_emmc_lba_0_16384.dd` (16,384 blocks = 8 MB, LBA 0x0–0x3FFF)
> **Tool:** Block density analysis (`python3`, per-512-byte-block non-zero count), entropy calculation, `strings` extraction, DTB magic detection (`d00dfeed`), ARM64 instruction disassembly.
> **Status:** ✅ Fully covers the entire hidden bootloader area up to `kernel1`. This supersedes all previous partial dumps.

### Complete Non-Zero Region Map

```
LBA  0x0000– 0x0003 (    0–    3):     2.0 KB   MBR + GPT headers
LBA  0x0028– 0x0028 (   40–   40):     0.5 KB   SPL IVT entry point
LBA  0x0044– 0x00ED (   68–  237):    85.0 KB   SPL code
LBA  0x00FD– 0x00FE (  253–  254):     1.0 KB   Sparse data
LBA  0x011B– 0x014B (  283–  331):    24.5 KB   Sparse code
LBA  0x015D– 0x0166 (  349–  358):     5.0 KB   Sparse code
LBA  0x0300– 0x0302 (  768–  770):     1.5 KB   U-Boot env (primary, compiled-in)
LBA  0x0308– 0x030F (  776–  783):     4.0 KB   U-Boot env strings (compiled-in)
LBA  0x0318– 0x098C (  792– 2444):   826.5 KB   U-Boot proper (main binary)
LBA  0x098E– 0x0991 ( 2446– 2449):     2.0 KB   TF-A tail (BL31 strings)
LBA  0x0996– 0x0997 ( 2454– 2455):     1.0 KB   TF-A/OP-TEE gap
LBA  0x099B– 0x09A3 ( 2459– 2467):     4.5 KB   TF-A continuation
LBA  0x09A7– 0x09A7 ( 2471– 2471):     0.5 KB   Sparse
LBA  0x09AB– 0x0BC7 ( 2475– 3015):   270.5 KB   OP-TEE OS binary
LBA  0x0BCF– 0x0C0B ( 3023– 3083):    30.5 KB   OP-TEE TA loader
LBA  0x0C0F– 0x0C89 ( 3087– 3209):    61.5 KB   OP-TEE kernel/crypto
LBA  0x0C8F– 0x0C9B ( 3215– 3227):     6.5 KB   OP-TEE secure storage tail
LBA  0x1997– 0x19B6 ( 6551– 6582):    16.0 KB   OP-TEE metadata / linker table
LBA  0x2000– 0x200A ( 8192– 8202):     5.5 KB   U-Boot env (redundant copy, runtime)

Total non-zero data: ~1.37 MB in ~4 MB area (rest is zeros)
```

### Detailed Region Breakdown

| LBA (hex) | LBA (dec) | Size | Content | Evidence |
|-----------|-----------|------|---------|----------|
| 0x0000 | 0 | 2 KB | **Protective MBR + GPT** | `file` command: "DOS/MBR boot sector". 0xAA55 at offset 510. GPT "EFI PART" at LBA 1. **Tool:** `file`, `xxd` |
| 0x0022–0x003F | 34–63 | 15 KB | **Zeros (GPT padding)** | All-zero blocks. **Tool:** density scan |
| **0x0040** | **64** | 0.5 KB | **SPL entry point** | First ARM64 instruction `d1002041` = `add x1, x8, #8` at byte 0x8000. i.MX8MN ROM loads SPL here. **Tool:** `xxd` |
| 0x0044–0x00ED | 68–237 | 85 KB | **SPL code** | Continuous ARM64 instructions. Contains DDR init, HAB, MMC boot code. **Tool:** density scan, `strings` |
| 0x005B | 91 | — | **SPL version** | `"U-Boot SPL 2020.04-1.7.0-2749_08020951_cfae4f98+gffc3fbe7e5 (Aug 02 2022 - 17:48:20 +0000)"` **Tool:** `strings` |
| 0x00FD–0x0166 | 253–358 | 30.5 KB | **Sparse early firmware code** | Mixed density, DDR init / low-level SoC code. **Tool:** density scan |
| 0x012C | ~300 | ~1 KB | **DTB (SPL FIT config)** | Magic `d00dfeed`, version 17, 1039 bytes. Contains FIT image strings. **Tool:** DTB magic search (python3) |
| 0x01F4–0x02F5 | 500–757 | ~130 KB | **Zeros (large gap)** | All-zero blocks between sparse SPL and U-Boot proper. **Tool:** density scan |
| 0x0300–0x030F | 768–783 | 5.5 KB | **U-Boot env (primary, compiled-in)** | Default env vars: `loadaddr`, `fdt_addr`, `bootcmd`, `mmcboot`, `reliable_boot`, `file_decrypt` etc. **Tool:** `strings` at LBA 760–770 (from earlier dump; confirmed in new dump at same LBA) |
| **0x0318–0x098C** | **792–2444** | **826.5 KB** | **U-Boot proper + FIT image** | Dense ARM64 code (85–100% block density, 6+ bits/byte entropy). Contains U-Boot core, MMC driver, fastboot, EFI boot manager, FDT library, encrypted boot commands. **Tool:** density scan, entropy, `strings` |
| 0x02F3 | ~755 | — | **U-Boot proper version** | `"U-Boot 2020.04-1.7.0-2749_08020951_cfae4f98+gffc3fbe7e5 (Aug 02 2022 - 17:48:20 +0000)"` **Tool:** `strings` |
| 0x038A–0x03DA | ~906–~986 | ~40 KB | **Embedded device tree (DTB)** | `fsl,imx8mn-gpio`, `fsl,imx8mn-ddr4-som`, `mmc@30b40000`, `caam-sm@00100000`, `serial@30890000` (ttymxc1). **Tool:** `strings` |
| **0x0988–0x098C** | **2440–2444** | **~2.5 KB** | **TF-A (Trusted Firmware-A) version + tail** | `"Built : 08:42:51, Nov  3 2021"`, `"v2.2(release):rel_imx_5.4.47_2.2.0-0-gc949a888e-dirty"`. Strings: `BL31`, `imx_sip_svc`, `opteed_std`, `opteed_fast`, `arm_arch_svc`, `PANIC at PC`. **Tool:** `strings`, DTB search (no DTB magic here — TF-A is raw AArch64 EL3 firmware) |
| 0x098E–0x09A3 | 2446–2467 | 11 KB | **TF-A sparse continuation** | Sparse non-zero blocks (16–432 bytes/block). **Tool:** density scan |
| **0x09AB–0x0C9B** | **2475–3227** | **~370 KB** | **OP-TEE OS** | Contains TA loader (`core/arch/arm/kernel/tee_ta_manager.c`, `core/arch/arm/kernel/user_ta.c`, `elf/ta_elf.c`), CAAM crypto drivers (`core/drivers/crypto/caam/caam_ctrl.c`, `caam_hash.c`, `caam_cipher_mac.c`, `caam_blob.c`), thread management, MMU, secure storage. CAAM init sequence: `caam_pwr_add_backup`, `caam_jr_init`, `caam_rng_init`, `caam_hash_init`, `caam_cipher_init`, `caam_hmac_init`, `caam_rsa_init`, `caam_ecc_init`, `caam_dsa_init`, `caam_dh_init`, `caam_mp_init`. DTB node `/firmware/optee` with `linaro,optee-tz` compatible. `tee_fs_ssk` secure storage key. **Tool:** `strings` at LBA 3074–3227 |
| 0x0C0F–0x0C89 | 3087–3209 | 61.5 KB | **OP-TEE kernel + crypto** | Dense ARM64 code. Includes `core/lib/libtomcrypt/ctr.c`, `gpd.tee.trustedStorage.antiRollback.protectionLevel`, manufacturing protection (`mppub_gen`, `mp_get_public_key`). **Tool:** density scan, `strings` |
| 0x0C8F–0x0C9B | 3215–3227 | 6.5 KB | **OP-TEE secure storage tail** | `tee_fs_ssk` string. Sparse tail end of OP-TEE binary. **Tool:** `strings` |
| 0x1997–0x19B6 | 6551–6582 | 16 KB | **OP-TEE metadata / linker table** | Structure with 0x10 header at offset 0x20, containing pointer pairs to ~0x5e20xxxx address range (upper RAM, likely TZDRAM). CAAM blob pattern (`0x80 0x00`) found at blob offset 13544. No ELF magic. Likely an OP-TEE linker/metadata section or secure storage index. **Tool:** hex dump (python3), pattern search |
| 0x1C80–0x1FFF | 7296–8191 | 444 KB | **Zeros** | All-zero padding between OP-TEE metadata and redundant env. **Tool:** density scan |
| **0x2000–0x200A** | **8192–8202** | **5.5 KB** | **U-Boot env (redundant runtime copy)** | Full set of runtime env vars. **bootcount=97** (boot loop!). Complete boot chain documented below. No valid CRC32 header — starts directly with `altbootcmd=` text. **Tool:** `strings`, CRC validation (python3) |

### Block Density Summary

| LBA Range | Non-Zero % | Entropy (bits/byte) | Content |
|-----------|-----------|---------------------|---------|
| 0x0000–0x003F (0–63) | 0.8% | 0.12 | MBR + GPT + padding |
| 0x0040–0x0063 (64–99) | 76.1% | 5.83 | SPL entry + early code |
| 0x0064–0x01F3 (100–499) | 39.2% | 3.84 | Sparse SPL code |
| 0x01F4–0x0317 (500–791) | 25.4% | 1.80 | Zero gap + env start |
| 0x0318–0x098C (792–2444) | 87.1% | 6.40 | U-Boot proper (dense) |
| 0x098D–0x099A (2445–2458) | 26.5% | — | TF-A sparse tail |
| 0x09AB–0x0C9B (2475–3227) | 81.5% | — | OP-TEE OS |
| 0x0C9C–0x1996 (3228–6550) | 0.0% | 0.00 | Zeros (3.2 MB gap) |
| 0x1997–0x19B6 (6551–6582) | 38.6% | 2.91 | OP-TEE metadata |
| 0x19B7–0x1FFF (6583–8191) | 0.0% | 0.00 | Zeros (784 KB gap) |
| 0x2000–0x200A (8192–8202) | 63.4% | 4.68 | U-Boot env (redundant) |
| 0x200B–0x3FFF (8203–16383) | 0.0% | 0.00 | Zeros (4 MB — all of kernel1 start) |

**Source:** All values from `dump_valid/2026-04-30_emmc_lba_0_16384.dd`. Density = per-block non-zero byte count. Entropy = Shannon entropy over region. **Tool:** `python3` (custom analysis script), `xxd`.

---

## Firmware Versions (verified)

| Component | Version | Build Date | Source LBA |
|-----------|---------|------------|------------|
| SPL | `2020.04-1.7.0-2749_08020951_cfae4f98+gffc3fbe7e5` | Aug 02 2022 17:48:20 | 0x005B |
| U-Boot proper | `2020.04-1.7.0-2749_08020951_cfae4f98+gffc3fbe7e5` | Aug 02 2022 17:48:20 | 0x02F3 |
| TF-A (BL31) | `v2.2(release):rel_imx_5.4.47_2.2.0-0-gc949a888e-dirty` | Nov 3 2021 08:42:51 | 0x0988 |
| OP-TEE OS | (version string not directly found — identified by source paths) | — | 0x09AB–0x0C9B |
| Board | `DDR4 SOM` / `iMX8MN` / `imx8mn-evk` | — | 0x2001 (env) |

**Source:** `strings` on `dump_valid/2026-04-30_emmc_lba_0_16384.dd`. **Tool:** `python3` regex `[\x20-\x7e]{10,}`.

**Note:** TF-A is older (Nov 2021) than U-Boot (Aug 2022) — TF-A was likely built separately by NXP/Emcraft as part of the `rel_imx_5.4.47_2.2.0` BSP release.

---

## SPL Location

SPL (IVT + first instruction) is at **byte offset 0x8000 in the user area** (LBA 0x40). This is set by the FCB in the eMMC boot partition (hardware partition 1/2), which `mmc read` cannot access. The ROM reads the FCB from the boot partition, which points to user area byte offset 0x8000. The standard i.MX8MN default is 0x4000 — Neato uses a custom 0x8000 offset.

**Evidence:** First ARM64 instruction `d1002041` (`add x1, x8, #8`) at LBA 0x40, byte 0x8000. Zeros at LBA 0x28 (byte 0x5000, the standard default). **Tool:** `xxd`, ARM64 disassembly.

---

## A/B Reliable Boot Mechanism

U-Boot implements a reliable A/B boot scheme using environment variables:

### Boot Selection Logic (from `reliable_boot` env var, LBA 0x2001)

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

### Recovery / Rollback Logic

- **`altbootcmd`** (LBA 0x2000): On `bootcount` expiry → swap `boot1_valid`/`boot2_valid`/`boot2_active`, call `rollback_uboot`, saveenv, reset. Has `low_battery_level` check to skip rollback during low battery.
- **`reliable_install`** (LBA 0x2001): Full reset: `upgrade_available=0`, `bootcount=0`, clear all valid/active flags, then `boot1_valid=1`.
- **`rollback_uboot`** (LBA 0x2001): `fatload mmc ${mmcdev}:${mmcpart} ${loadaddr} imx-boot.bin && mmc write $loadaddr 40 1fc0` — writes new U-Boot to LBA 40 (0x28), length 0x1FC0 sectors (~1.0 MB). This overwrites SPL + U-Boot proper + TF-A + OP-TEE in one shot.

**Source:** U-Boot env strings at LBA 0x2000–0x200A. **Tool:** `strings`.

---

## Encrypted Boot Chain

All firmware components loaded from the FAT filesystem are encrypted. Decryption uses a key blob loaded via `loadkeyblob`.

### Load Sequence (from `mmcboot` env, LBA 0x2003)

```
1. loadkeyblob → fatload key_blob.enc → 0x45000000
2. loadimage   → fatload Image.enc → file_decrypt → 0x40480000
3. loadfdt     → fatload emcraft-imx8mn-ddr4-som.dtb.enc → file_decrypt → 0x43000000
4. loadinitrd  → fatload initrd.uImage.enc → file_decrypt → 0x43800000
5. loadswuk    → fatload swu-pubk.pem.enc → file_decrypt → 0x43100000 (if HAB version exists)
6. loadsig     → fatload *.sig.enc → file_decrypt → after kernel (if HAB version exists)
7. booti ${loadaddr} ${initrd_addr} ${fdt_addr}
```

### Key Addresses

| Variable | Address | Purpose |
|----------|---------|---------|
| `loadaddr` | `0x40480000` | Kernel image |
| `fdt_addr` | `0x43000000` | Device tree |
| `initrd_addr` | `0x43800000` | Initramfs |
| `enc_file_addr` | `0x46000000` | Temporary encrypted file buffer |
| `keyblob_addr` | `0x45000000` | Encryption key blob |
| `swuk_addr` | `0x43100000` | SWU public key |

### Encrypted Files on FAT Partition

| File | Purpose |
|------|---------|
| `key_blob.enc` | CAAM decryption key blob |
| `Image.enc` | Linux kernel |
| `emcraft-imx8mn-ddr4-som.dtb.enc` | Device tree |
| `initrd.uImage.enc` | Initramfs |
| `swu-pubk.pem.enc` | Software update public key |
| `*.sig.enc` | Kernel/DTB/initrd signature |

### `file_decrypt` Command

Custom U-Boot command that decrypts using CAAM (Cryptographic Accelerator and Assurance Module). Found at LBA 0x7D1 in compiled-in env. Arguments: `<keyblob_addr> <keyblob_size> <enc_addr> <dec_addr> <size>`.

**Source:** U-Boot env vars at LBA 0x2000–0x200A. Encrypted file names also found in compiled-in env at LBA 0x758. **Tool:** `strings`.

---

## U-Boot Environment Variables (runtime copy at LBA 0x2000)

> Primary env (compiled-in defaults) at LBA ~768. Runtime copy at LBA 8192 (0x2000).
> No valid CRC32 header found — the runtime copy starts directly with env data text.

### Boot State

| Variable | Value | Interpretation |
|----------|-------|---------------|
| `boot1_valid` | `1` | Slot 1 is valid |
| `boot2_active` | `0` | Currently trying slot 1 |
| `boot2_valid` | `1` | Slot 2 is valid (fallback) |
| `bootcount` | **`97`** | **⚠️ Stuck in boot loop!** |
| `upgrade_available` | `1` | Upgrade tracking active |
| `swu_upgrade_done` | `0` | No pending upgrade |
| `reset_cause` | `1` | Last reset cause code |
| `platform` | `lego` | Neato model (D8 "Lego"?) |

### System Config

| Variable | Value |
|----------|-------|
| `baudrate` | `115200` |
| `console` | `ttymxc1,115200` |
| `board_name` | `DDR4 SOM` |
| `board_rev` | `iMX8MN` |
| `soc_type` | `imx8mn` |
| `mmcdev` | `2` |
| `mmcpart` | `1` |
| `emmc_dev` | `2` |
| `sd_dev` | `1` |
| `serial#` | `3610b209dab58857` |
| `bootdelay` | `0` |
| `silent` | `1` |
| `boot_fit` | `no` |
| `mmcautodetect` | `yes` |
| `fastboot_dev` | `mmc2` |
| `fdt_high` | `0xffffffffffffffff` |
| `initrd_high` | `0xffffffffffffffff` |

### Boot Commands

| Variable | Value (abbreviated) |
|----------|-------------------|
| `bootcmd` | `mmc dev ${mmcdev}; mmc rescan; run reliable_boot; ...` |
| `mmcroot` | `/dev/mmcblk2p2 rootwait rw` |
| `mmcargs` | `setenv bootargs ${jh_clk} console=${console} quiet=quiet reset_cause=${reset_cause} platform=${platform}` |
| `mmcboot` | Load keyblob → image → DTB → initrd → swuk → sig → `booti` |
| `image` | `Image.enc` |
| `fdt_file` | `emcraft-imx8mn-ddr4-som.dtb.enc` |
| `initrd_file` | `initrd.uImage.enc` |
| `keyblob_file` | `key_blob.enc` |
| `swuk_file` | `swu-pubk.pem.enc` |
| `script` | `boot.scr` |

### JTAG/Hardware Debug

| Variable | Value |
|----------|-------|
| `jh_clk` | (empty) |
| `jh_mmcboot` | `mw 0x303d0518 0xff; setenv fdt_file ${jh_root_dtb}; setenv jh_clk clk_ignore_unused; if run loadimage; then run mmcboot; else run jh_netboot; fi` |
| `jh_root_dtb` | `imx8mn-som-root.dtb` |
| `load_uboot` | `fatload mmc ${mmcdev}:${mmcpart} ${loadaddr} imx-boot.bin` |

**Source:** All from `dump_valid/2026-04-30_emmc_lba_0_16384.dd`, LBA 0x2000–0x200A. **Tool:** `strings`, manual parsing of `key=value\0` format (python3).

---

## Embedded Device Tree (at LBA 0x0905)

A full Flattened Device Tree is embedded in the bootloader binary:

| Property | Value |
|----------|-------|
| **Magic** | `0xd00dfeed` |
| **Version** | 17 (FDT version 17) |
| **Total size** | 28,851 bytes (28.2 KB) |
| **Location** | LBA 2309 (0x0905) byte offset 0x120BB0, spanning to LBA 2366 (0x093E) |
| **Compatible** | `emcraft,imx8mn-ddr4-som` / `fsl,imx8mn` |
| **Description** | "7Emcraft i.MX8MN DDR4 SOM board" |

### Notable DT Nodes

| Node / Compatible | Address | Purpose |
|--------------------|---------|---------|
| `caam-sm@00100000` | 0x00100000 | CAAM secure memory |
| `serial@30890000` | 0x30890000 | UART2 = ttymxc1 (debug console) |
| `serial@30860000` | 0x30860000 | UART1 = ttymxc0 |
| `serial@30880000` | 0x30880000 | UART3 = ttymxc2 |
| `serial@30a60000` | 0x30a60000 | UART4 = ttymxc3 |
| `mmc@30b50000` | 0x30b50000 | USDHC2 (eMMC) |
| `mmc@30b40000` | 0x30b40000 | USDHC1 (SD card) |
| `mmc@30b60000` | 0x30b60000 | USDHC3 (unused?) |
| `spi@30bb0000` | 0x30bb0000 | FlexSPI (NOR flash) |
| `usb@32e40000` | 0x32e40000 | USB1 (OTG) |
| `usb@32e50000` | 0x32e50000 | USB2 |
| `lcd-controller@32e00000` | 0x32e00000 | LCDIF display |
| `mipi-dsim` | — | MIPI DSI display |
| `fsl,imx8mn-fec` | — | Ethernet (FEC) |
| `fsl,imx8mn-gpmi-nand` | — | NAND flash controller |
| `fsl,imx8mn-ocotp` | — | OTP fuses (eFuse) |
| `fsl,sec-v4.0` | — | CAAM crypto engine |
| `snvs-powerkey` | 0x30370000 | SNVS power key |
| `gpio@30200000–30240000` | — | GPIO1–5 |
| `fsl,imx8mn-wdt` | — | Watchdog timer |
| `fsl,imx8mn-tmu` | — | Thermal management |

**Source:** DTB at LBA 0x0905 in `dump_valid/2026-04-30_emmc_lba_0_16384.dd`. Parsed via DTB header (magic `d00dfeed`, struct.unpack). **Tool:** `python3` (custom DTB parser + regex string extraction).

---

## OP-TEE / TF-A Details

### TF-A (Trusted Firmware-A) — BL31

| Property | Value |
|----------|-------|
| Version | `v2.2(release):rel_imx_5.4.47_2.2.0-0-gc949a888e-dirty` |
| Build date | Nov 3 2021 08:42:51 |
| Location | LBA ~2440–2467 (sparse, ~11 KB) |
| Source paths | `BL31`, `imx_sip_svc`, `opteed_std`, `opteed_fast`, `arm_arch_svc` |

### OP-TEE OS

| Property | Value |
|----------|-------|
| Location | LBA 2475–3227 (~370 KB) |
| Source paths | `core/arch/arm/kernel/`, `core/drivers/crypto/caam/`, `core/lib/libtomcrypt/` |
| Crypto backends | CAAM (primary), libtomcrypt (software fallback) |
| CAAM drivers | `caam_ctrl`, `caam_jr` (job ring), `caam_hash`, `caam_cipher`, `caam_hmac`, `caam_rsa`, `caam_ecc`, `caam_dsa`, `caam_dh`, `caam_mp`, `caam_blob`, `caam_cmac`, `caam_sm` (secure memory) |
| Secure storage | `tee_fs_ssk` key, anti-rollback protection |
| Manufacturing | `mppub_gen`, `mp_get_public_key` (CAAM manufacturing protection) |
| DTB integration | `/firmware/optee` node, `linaro,optee-tz` compatible |

**Source:** `dump_valid/2026-04-30_emmc_lba_0_16384.dd`, LBA 2475–3227. **Tool:** `strings` with `[\x20-\x7e]{10,}` regex, filtered for source paths and OP-TEE identifiers.

---

## ⚠️ STALE — Old Dumps (pre-hex fix)

> **Source:** Dumps before 2026-04-30 that used decimal LBA numbers which U-Boot interpreted as hex for blocks ≥10.
> **The actual LBA mapping for these dumps is unknown/scrambled. Do not trust LBA values below.**
> Byte offsets within blocks may still be correct, but the block-to-LBA mapping is wrong.

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
| **`dump_valid/2026-04-30_emmc_lba_0_16384.dd`** | **0x0–0x3FFF** | **✅ Yes** | **8.0 MB** | **2026-04-30** | **Full bootloader area. Supersedes all previous partial dumps.** |
| `dump_valid/2026-04-30_emmc_lba_0_2200_try1.dd` | 0x0–0x897 | ✅ Yes (subset) | 1.1 MB | 2026-04-30 | Subset of above. Old "zero gap at 500-999" was wrong — actually 500-757 is zero, 758+ has data |
| `dump_valid/2026-04-30_emmc_lba_5521408_2000.dd` | 0x544000+ | ✅ Yes | 1.0 MB | 2026-04-30 | `/var/log` partition (ext4, 952 MB) |
| `dumps/DTB_lego_lba_24803.dtb` | unknown | ❌ LBA wrong | 24 KB | 2026-04-30 | Valid DTB, actual LBA unknown |
| `dumps/DTB_prime_lba_24852.dtb` | unknown | ❌ LBA wrong | 26 KB | 2026-04-30 | Valid DTB, actual LBA unknown |
| `dumps/2026-04-28_emmc_dump_lba_0_50000_115200_minicorupted.dd` | scrambled | ❌ | 25.6 MB | 2026-04-28 | Hex/decimal bug |
| `dumps/2026-04-30_emmc_dump_lba_50000_50000_115200_minicorupted.dd` | scrambled | ❌ | 25.6 MB | 2026-04-30 | Hex/decimal bug |
| `emmc_blocks_0_2048.dd` | scrambled | ❌ | 1.0 MB | 2026-04-27 | Hex/decimal bug |

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

---

## Open Questions

1. **~~Large zero gap at LBA 500–999~~** — RESOLVED: Zero gap is LBA 500–757 (~130 KB). U-Boot proper starts at LBA 792. Old dump was corrupt for this range.
2. **~~What's beyond LBA 2199?~~** — RESOLVED: TF-A (LBA 2440–2467), OP-TEE OS (LBA 2475–3227), OP-TEE metadata (LBA 6551–6582), redundant U-Boot env (LBA 8192–8202). Rest is zeros up to kernel1.
3. **`bootcount=97`** — Device is deeply stuck in a boot loop. `bootlimit` not found in env (likely compiled-in default, probably 3). The boot loop isn't triggering `altbootcmd` — why?
4. **`platform=lego`** — Confirms this is a Neato "Lego" platform variant. What's the difference to "prime" or "frost"? (`neato-prime.dtb.enc`, `neato-frost.dtb.enc` strings found in compiled-in env)
5. **OP-TEE metadata at LBA 6551–6582** — Structure with pointers to 0x5e20xxxx (TZDRAM). CAAM blob pattern present. Purpose unclear — linker table? Secure storage index? Key blob container?
6. **`serial#=3610b209dab58857`** — Device-unique serial, used for identification/updates.
7. **The `user` partition** — what filesystem? Needs fresh dump to verify.
8. **rfs1 encryption** — UART dump of rfs1 shows 8.0 bits/byte entropy, confirming the root filesystem is encrypted (as expected from the encrypted boot chain).
9. **Boot failure root cause** — With `bootcount=97`, the device keeps rebooting but never triggers `altbootcmd` rollback. Possible: `bootlimit` > 97, or the boot command doesn't increment `bootcount`, or `upgrade_available` logic prevents it.
10. **`rollback_uboot` writes 0x1FC0 sectors (~1 MB) to LBA 40** — This would overwrite everything from SPL through OP-TEE. Confirms the entire LBA 40–2444 region is the monolithic `imx-boot.bin` FIT image.
