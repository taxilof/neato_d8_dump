# U-Boot Scripts in Neato D8 Bootloader Dump

This document explains the extracted U-Boot environment variable scripts from the eMMC dump `2026-04-30_emmc_lba_0_16384.dd` at LBA 0x2000 (runtime env). These are command sequences stored as strings in U-Boot's environment, defining boot behavior for the Neato D8 device (i.MX8MN-based robot vacuum).

The scripts were extracted using `strings` on the dump and saved as individual `.txt` files for reference. They implement an A/B reliable boot system with encryption (CAAM-based), rollback on failure, and manufacturing/debug modes. The device is currently stuck in a boot loop (`bootcount=97`), trying boot slot 1 (`boot1_valid=1`, `boot2_active=0`).

All script contents are embedded below for easy sharing/reading. The separate `.txt` files contain the same formatted content.

## Overview

- **Location**: Runtime environment copy at LBA 0x2000–0x200A (5.5 KB). Primary compiled-in defaults at LBA 0x300–0x30F.
- **Format**: Key-value pairs in `name=value\0` format. Values are U-Boot command sequences.
- **Key Dependencies**:
  - Addresses: `loadaddr=0x40480000` (kernel), `fdt_addr=0x43000000` (DTB), `initrd_addr=0x43800000` (initrd), `keyblob_addr=0x45000000` (encryption key).
  - Files (encrypted on FAT partition in kernel1/kernel2): `key_blob.enc`, `Image.enc`, `emcraft-imx8mn-ddr4-som.dtb.enc`, `initrd.uImage.enc`, `swu-pubk.pem.enc`, `*.sig.enc`.
  - Partition: `mmcdev=2` (eMMC), `mmcpart=1` or `2` (kernel1/kernel2).
  - Boot Slots: Slot 1 (kernel1 LBA 0x4000, rfs1 LBA 0x44000), Slot 2 (kernel2 0x24000, rfs2 0x2C4000).
- **Encryption**: All files decrypted via custom `file_decrypt` command using CAAM hardware accelerator.
- **Reliable Boot**: Attempts slot 1 first, falls back to slot 2 after failures (`bootcount` exceeds limit). Rollback overwrites bootloader on expiry.

## Script Breakdown

### 1. bootcmd
**What it does**: Main boot entry point. Scans eMMC, runs reliable A/B boot selection. If upgrade pending, resets. Fallback to direct `booti` if scan fails.

**Full formatted content** (from bootcmd.txt):
```
mmc dev ${mmcdev}
if mmc rescan; then
    run reliable_boot
    if test x$upgrade_available = x1; then
        reset
    fi
else
    booti ${loadaddr} - ${fdt_addr}
fi
```

**Achievements by running**:
- Initializes eMMC (device 2).
- Rescans for partitions.
- Delegates to `reliable_boot` for A/B slot selection and boot.
- If upgrade available, triggers immediate reset (likely for SWU/OTA).
- Fallback: Boots kernel at `loadaddr` without initrd/DTB (emergency mode).
- **Use case**: Default power-on boot sequence. Safe to run in stuck states to retry boot.

### 2. altbootcmd
**What it does**: Rollback/alternate boot handler. Checks battery level before switching slots. Swaps active/valid flags between boot slots, runs `rollback_uboot` to update bootloader, marks upgrade done, resets bootcount, saves env, and reboots.

**Full formatted content** (from altbootcmd.txt):
```
if test x$low_battery_level = xyes; then
    echo Skip rollback due to low battery level
    run bootcmd
fi

if test x$boot2_active != x1; then
    setenv boot2_active 1
    setenv boot2_valid 1
    setenv boot1_valid 0
    setenv mmcpart 2
else
    setenv boot2_active 0
    setenv boot2_valid 0
    setenv boot1_valid 1
    setenv mmcpart 1
fi

run rollback_uboot
setenv upgrade_available 1
setenv swu_upgrade_done 1
setenv bootcount 0
saveenv
reset
```

**Achievements by running**:
- Skips if low battery (avoids risky writes).
- Switches to inactive slot (e.g., from 1 to 2 or vice versa).
- Updates bootloader via `rollback_uboot` (writes new `imx-boot.bin` to LBA 40, overwriting SPL/U-Boot/TF-A/OP-TEE).
- Flags upgrade complete and resets counters.
- Saves env and reboots to try new slot.
- **Use case**: Manual rollback. Run after boot failures to force slot swap and bootloader refresh. Caution: Overwrites entire bootloader (~1 MB).

### 3. reliable_boot
**What it does**: A/B boot selector. Clears recovery status, determines active slot based on flags (`boot1_valid`, `boot2_active`, `boot2_valid`). Sets rootfs device and partition. Runs `mmcboot` on selected slot. On failure, suggests `reliable_install` or USB fastboot.

**Full formatted content** (from reliable_boot.txt):
```
if test x$recovery_status != x; then
    echo WARNING: recovery_status=$recovery_status
    setenv recovery_status
    saveenv
fi

setenv boot_num 0

if test x$boot2_active != x1 -a x$boot1_valid = x1; then
    setenv boot_num 1
    setenv mmcroot /dev/mmcblk2p3 rootwait rw
fi

if test x$boot2_active = x1 -a x$boot2_valid = x1; then
    setenv boot_num 2
    setenv mmcroot /dev/mmcblk2p4 rootwait rw
fi

if test x$boot_num != x0; then
    echo \"Booting Image Set #${boot_num}\"
    setenv mmcpart $boot_num
    run mmcboot ||
        echo ERROR: mmcdboot($boot_num) failed, try running reliable_install
else
    echo ERROR: Active image set is invalid, try running reliable_install
fi

echo ERROR: Failed to boot, switching to USB boot
fastboot 0
```

**Achievements by running**:
- Resets any recovery flag and saves env.
- Prioritizes slot 1 if valid and not active on slot 2.
- Sets slot 2 if active and valid.
- Configures root (`/dev/mmcblk2p3` for slot 1, `p4` for slot 2).
- Boots selected slot via `mmcboot`.
- On error: Logs failure, enters fastboot (USB recovery).
- **Use case**: Core A/B logic. Run to test slot validity. Currently selects slot 1 (boot_num=1).

### 4. mmcboot
**What it does**: Loads and boots encrypted images from selected kernel partition. Sets bootargs, loads/decrypts keyblob, kernel (`Image.enc`), DTB, initrd, SWU pubkey (if HAB), signature. Boots via `booti` (ARM64 kernel loader). Warns on missing components.

**Full formatted content** (from mmcboot.txt):
```
echo Booting from mmc ...
run mmcargs

if test ${boot_fit} = yes || test ${boot_fit} = try; then
    bootm ${loadaddr}
else
    if run loadkeyblob; then
        if run loadimage; then
            if run loadfdt; then
                if run loadinitrd; then
                    if run loadswuk; then
                        if run loadsig; then
                            booti ${loadaddr} ${initrd_addr} ${fdt_addr}
                        else
                            echo WARN: Cannot load signature
                        fi
                    else
                        echo WARN: Cannot load .swu public key
                    fi
                else
                    echo WARN: Cannot load initrd
                fi
            else
                echo WARN: Cannot load the DT
            fi
        else
            echo WARN: Cannot load the kernel image
        fi
    else
        echo WARN: Cannot load the encryption key blob
    fi
fi
```

**Achievements by running**:
- Prepares args (console, quiet, reset_cause, platform=lego).
- Skips FIT if disabled (`boot_fit=no`).
- Chain-loads: keyblob → kernel → DTB → initrd → pubkey → sig.
- Decrypts each with `file_decrypt` (CAAM).
- Loads sig to `sig_addr` after kernel.
- Boots kernel with initrd and DTB.
- **Use case**: Standard OS boot from eMMC. Fails if files missing/encrypted wrong. Current failure point: Likely decryption or file load.

### 5. reliable_install
**What it does**: Factory reset of boot state. Clears upgrade/boot flags, sets recovery temp, resets env, then marks slot 1 valid.

**Full formatted content** (from reliable_install.txt):
```
setenv upgrade_available 0
setenv bootcount 0
setenv boot1_valid 0
setenv boot2_valid 0
setenv boot2_active 0
setenv recovery_status tmp
setenv recovery_status
saveenv
setenv boot1_valid 1
saveenv
```

**Achievements by running**:
- Resets counters and flags (upgrade=0, bootcount=0, slots invalid, active=0).
- Sets temporary recovery, clears it.
- Saves env twice: Once after reset, then sets boot1_valid=1.
- **Use case**: Recover from invalid state. Run when both slots invalid to default to slot 1. Fix for boot loop if flags corrupted.

### 6. rollback_uboot
**What it does**: Updates bootloader. Loads `imx-boot.bin` from FAT, writes it to LBA 40 (overwriting SPL to OP-TEE, ~1 MB / 0x1FC0 blocks).

**Full formatted content** (from rollback_uboot.txt):
```
if run load_uboot; then
    mmc write $loadaddr 40 1fc0
fi
```

**Achievements by running**:
- Loads U-Boot binary to `loadaddr`.
- Writes raw to eMMC starting LBA 40 (0x28 hex = 40 dec, but layout suggests 0x40=64 dec for SPL; likely a custom offset).
- Refreshes entire bootloader chain.
- **Use case**: Bootloader recovery. Risky—overwrites firmware. Run only if new `imx-boot.bin` on FAT.

### Sub-Load Commands (Helpers for mmcboot)

#### loadkeyblob
**What it does**: Loads the encryption key blob from the FAT partition to prepare for CAAM decryption.

**Full formatted content** (from loadkeyblob.txt):
```
fatload mmc ${mmcdev}:${mmcpart} ${keyblob_addr} ${keyblob_file}
setenv keyblob_size ${filesize}
```

**Achievements by running**:
- Loads `key_blob.enc` to `keyblob_addr` and sets its size var.
- Essential prerequisite for all file decryption steps.

#### loadimage
**What it does**: Loads and decrypts the Linux kernel image from the FAT partition.

**Full formatted content** (from loadimage.txt):
```
fatload mmc ${mmcdev}:${mmcpart} ${enc_file_addr} ${image}
file_decrypt ${keyblob_addr} ${keyblob_size} ${enc_file_addr} ${loadaddr} ${filesize}
setexpr sig_addr ${loadaddr} + ${filesize}
```

**Achievements by running**:
- Loads `Image.enc` to temp buffer, decrypts to `loadaddr` (0x40480000).
- Calculates position for signature file.
- Prepares decrypted kernel for booting; fails without prior keyblob load.

#### loadfdt
**What it does**: Loads and decrypts the device tree blob (DTB) from the FAT partition.

**Full formatted content** (from loadfdt.txt):
```
fatload mmc ${mmcdev}:${mmcpart} ${enc_file_addr} ${fdt_file}
file_decrypt ${keyblob_addr} ${keyblob_size} ${enc_file_addr} ${fdt_addr} ${filesize}
setexpr sig_file sub .dtb. .sig. ${fdt_file}
```

**Achievements by running**:
- Loads `emcraft-imx8mn-ddr4-som.dtb.enc` to temp, decrypts to `fdt_addr` (0x43000000).
- Derives signature filename (e.g., from .dtb.enc to .sig.enc).
- Provides hardware configuration to the kernel.

#### loadinitrd
**What it does**: Loads and decrypts the initramfs from the FAT partition.

**Full formatted content** (from loadinitrd.txt):
```
fatload mmc ${mmcdev}:${mmcpart} ${enc_file_addr} ${initrd_file}
file_decrypt ${keyblob_addr} ${keyblob_size} ${enc_file_addr} ${initrd_addr} ${filesize}
```

**Achievements by running**:
- Loads `initrd.uImage.enc` to temp, decrypts to `initrd_addr` (0x43800000).
- Supplies initial filesystem for early kernel boot (e.g., drivers, mounts).

#### loadswuk
**What it does**: Conditionally loads and decrypts the SWU (Software Update) public key if secure boot (HAB) is enabled.

**Full formatted content** (from loadswuk.txt):
```
if hab_version; then
    fatload mmc ${mmcdev}:${mmcpart} ${enc_file_addr} ${swuk_file}
    file_decrypt ${keyblob_addr} ${keyblob_size} ${enc_file_addr} ${swuk_addr} ${filesize}
else
    echo skip swuk
fi
```

**Achievements by running**:
- Only if HAB active: Loads/decrypts `swu-pubk.pem.enc` to `swuk_addr` (0x43100000).
- Enables verification of signed OTA updates; skips otherwise to avoid errors.

#### loadsig
**What it does**: Conditionally loads and decrypts the signature file for the kernel/DTB/initrd (for HAB verification).

**Full formatted content** (from loadsig.txt):
```
if hab_version; then
    fatload mmc ${mmcdev}:${mmcpart} ${enc_file_addr} ${sig_file}
    file_decrypt ${keyblob_addr} ${keyblob_size} ${enc_file_addr} ${sig_addr} ${filesize}
else
    echo skip signature
fi
```

**Achievements by running**:
- Only if HAB active: Loads/decrypts `${sig_file}` (e.g., kernel.sig.enc) to `sig_addr` (after kernel in memory).
- Ensures integrity/authenticity of boot images; skips if no HAB.

### JTAG/Debug Commands

#### jh_mmcboot
**What it does**: JTAG-assisted MMC boot mode—disables clock watchdog, sets custom root DTB, ignores unused clocks, then attempts loadimage and mmcboot (falls to netboot on fail).

**Full formatted content** (from jh_mmcboot.txt):
```
mw 0x303d0518 0xff
setenv fdt_file ${jh_root_dtb}
setenv jh_clk clk_ignore_unused
if run loadimage; then
    run mmcboot
else
    run jh_netboot
fi
```

**Achievements by running**:
- Writes to register 0x303d0518 (likely CCM_CLPCR or similar for clk control).
- Uses `imx8mn-som-root.dtb` and adds `clk_ignore_unused` to bootargs.
- Runs encrypted MMC boot or netboot fallback.
- **Use case**: Debug/recovery during hardware development (e.g., with JTAG probe).

#### jh_netboot
**What it does**: JTAG-assisted network boot—disables clock watchdog, sets custom root DTB and clock ignore, then runs netboot (TFTP/NFS).

**Full formatted content** (from jh_netboot.txt):
```
mw 0x303d0518 0xff
setenv fdt_file ${jh_root_dtb}
setenv jh_clk clk_ignore_unused
run netboot
```

**Achievements by running**:
- Same overrides as jh_mmcboot.
- Delegates to standard netboot (loads kernel/DTB via DHCP/TFTP).
- **Use case**: Network-based recovery when MMC is unavailable.

#### load_uboot
**What it does**: Loads the full U-Boot binary (`imx-boot.bin`) from the FAT partition for potential reflashing.

**Full formatted content** (from load_uboot.txt):
```
fatload mmc ${mmcdev}:${mmcpart} ${loadaddr} imx-boot.bin
```

**Achievements by running**:
- Loads to `loadaddr` (0x40480000) for immediate use (e.g., in `mmc write` for rollback).
- Prepares the entire bootloader image (SPL + U-Boot + TF-A + OP-TEE).
- **Use case**: Step 1 of bootloader update; pair with `rollback_uboot` for full refresh.

## Extraction Notes

- Extracted from runtime env strings at LBA 0x2000.
- Primary env (LBA 0x300) has defaults but fewer custom scripts (mostly addresses/files).
- No external `boot.scr` found in dump— all inline.
- To run: In U-Boot console (UART), `run bootcmd` etc. Use `editenv` to modify.
- Current Issue: `bootcount=97` indicates loop, but no rollback triggered (bootlimit >97?). Run `setenv bootcount 0; saveenv; run bootcmd` to test.

## Recommendations

- To fix loop: Run `reliable_install` then `bootcmd`.
- For recovery: Enter fastboot (USB), flash new images.
- Verify files on kernel1 FAT: Use `fatload` manually.
- Full env dump: `printenv` in U-Boot.

For more, see emmc_layout.md in project root.