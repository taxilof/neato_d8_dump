# Neato D8 — Keys, Cryptography & SWU Update

Cryptographic keys and encryption architecture extracted from Neato D8 (i.MX8M Nano) eMMC and RAM dumps.

---

## 1. RSA Keys (Extracted)

All keys are 2048-bit RSA with public exponent 65537 (0x10001).

| Key | Type | Source | eMMC Partition |
|-----|------|--------|----------------|
| `private_key.pem` | RSA 2048 Private Key (PKCS#8) | User partition UART dump | `user` (LBA 0x544000) |
| `public_key_user_partition.pem` | RSA 2048 Public Key (SubjectPublicKeyInfo) | User partition UART dump | `user` (LBA 0x544000) |
| `public_key_boot_partition.pem` | RSA 2048 Public Key (SubjectPublicKeyInfo) | Boot/kernel1 UART dump | `kernel1` (LBA 0x4000) |
| `cert_csf1_1_sha256_2048.pem` | X.509 Certificate (CSF) | binwalk from kernel1 dump | `kernel1` (LBA 0x4000) |
| `cert_img1_1_sha256_2048.pem` | X.509 Certificate (IMG) | binwalk from kernel1 dump | `kernel1` (LBA 0x4000) |

### Key Relationships

- **Private Key ↔ Public Key (user)**: Same modulus → verified matching pair
- **Public Key (boot)**: Different modulus → different key pair
- **CSF1 / IMG1 certificates**: Different moduli → separate HAB key pairs

### Key Pair Verification

```bash
# Test 1: Sign with private key, verify with public key
echo "Hello Neato" > /tmp/test_msg.txt
openssl dgst -sha256 -sign private_key.pem -out /tmp/test_sig.bin /tmp/test_msg.txt
openssl dgst -sha256 -verify public_key_user_partition.pem -signature /tmp/test_sig.bin /tmp/test_msg.txt
# Output: Verified OK

# Test 2: Encrypt with public key, decrypt with private key
echo "secret_message" > /tmp/test_plain.txt
openssl pkeyutl -encrypt -in /tmp/test_plain.txt -out /tmp/test_enc.bin -inkey public_key_user_partition.pem -pubin
openssl pkeyutl -decrypt -in /tmp/test_enc.bin -out /tmp/test_dec.txt -inkey private_key.pem
cat /tmp/test_dec.txt
# Output: secret_message
```

Both tests pass. `private_key.pem` and `public_key_user_partition.pem` are a matching RSA-2048 key pair.

### PEM Blocks

**Private Key** (PKCS#8, unencrypted):

```
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDJCtxzskzruF7i
e2NG3xiy6odyUIMsOJycf2qI0xZcry0Rp+ZaJsuGIBqKhy09vJpeKL+pcQo1Iim0
hUK5T51FtoEO4QMwpii8X8PmyI8WLg1AkD7xkbNf9ghQz7b5JrtSfQf3IArAr6jf
S8CTHmQpOAWSqYQa8Oyrh89QE4xZYEJ1C3asNlq4HL2SkNm67skhwRVX2Uxj71we
TjempMXUnjoNSM3Xyv4Y7fQ5GT/Pv4oHf6UjX9veaf9Un/CnhbK347C7x5TWBr9O
QfiBoPsqrTK0IoGOYssBpu9bQ6tGn03D0I304NAM0StSYI55q305B7bzBhFc/0ik
g8Y1MxlDAgMBAAECggEAWeo4pKonCvn/ve2PfkADbOnFwFPQBvQe30OBY0Z9ZuCW
GKJuPP3C4u7yz+gbTNRQejJhXigHd7Ia0vkS2YyI+4ffescaRSTbbTyrgklK7ZGV
Lb4V2Lbgcde46mOsIwy2lPMEn/s9s+YcchoQO/xIscKzg1+7jM0aHLF2AAtuJv5B
6IEmietWKfLu6H6CzM+55jkIc3MUYnbn7xp+0aCJAnjtL82kYMiRFhYuz5OAIPDc
0RDJndn0wZb/zmofkX8wwRZNRasFtH7u2rJzbGsvvlYpLzaQumpXfsuDS8IQnijz
iW0xMvMFkVqW+kh6d6nJFzVgpmVFeLnuHlPUJMs/uQKBgQDzpuardVOu9TmTu7XR
yOyy+UTlOWfg8ZXRWdKGYlQ0M+zldV+us7RmkKZCVEyoe483GPtcC45IZzOR0fYb
9bhQkLvPTQGJAkjOuZejLpXvgd3N3E42SuO665x4KvqfSEFSld57KSUeSuLIq0oX
+MV8/NnyUg9Xt0f6ie1Pxxxu3wKBgQDTOya7e+bn+quJ0AfeURBF4Xhdh/YvfgZE
9Qo/ipfv2WTVPxaQCmk3SZyf3Dy6gVfdUkL3oEx0/zpl87LM/F2qZcTO/uO2SpHz
4qgYqx6Su9MgovlIXTnSMkKWxt9auB+6eavLeS/cGKhc1AmJ8+VSYusacQhebiW2
Qyp/nNi2HQKBgQDkzo8/5GY5nr/7JAOShgUB7WPtfwM2EqiGeLtix2Qbwcdtk9PO
06NNzfjTwSZb8eyD6UnjHlb3VzLudSWRDCeSQNidy8rtRt/oghEMhOr4iBQrBf/M
rHc/SZMepf3FJq1xSJwtPG5HDDv8Bh8Gc+/BeBGTpcwSq2NEu9HHYUwqMQKBgAre
REPpQBw3fZP9rCn4Kcouq67ETBptdY0evoQ+cUrZ+KIwOMz4fCloFDL1dfpypT6x
+Ngc21I5v5t3Sn/ZjEg0LEgqPTUn6RKPWu7J/yy1lUtcl07t3Qe/pkVzvhJA3wEN
OZWiip/cdO0xy7vZXLc8d7RIlJGnQTF7izg9rbjRAoGADFfqHLLE6p9tjBjy/FTb
r6Hc0M+s4A7drAIUI5mJ/7BA6xiKzc3pYTl8fEc3Ootrlv6vduW0fcLEfK0vimoE
gF6K5pmAXkvy3B47UkWJdvZXl/8rD/uoMTuscwzOCIXyIgzZYSGR97cuivr3J6AH
agZgadtUbO9esyw3sqjV2DE=
-----END PRIVATE KEY-----
```

**Public Key — User Partition** (SubjectPublicKeyInfo):

```
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyQrcc7JM67he4ntjRt8Y
suqHclCDLDicnH9qiNMWXK8tEafmWibLhiAaioctPbyaXii/qXEKNSIptIVCuU+d
RbaBDuEDMKYovF/D5siPFi4NQJA+8ZGzX/YIUM+2+Sa7Un0H9yAKwK+o30vAkx5k
KTgFkqmEGvDsq4fPUBOMWWBCdQt2rDZauBy9kpDZuu7JIcEVV9lMY+9cHk43pqTF
1J46DUjN18r+GO30ORk/z7+KB3+lI1/b3mn/VJ/wp4Wyt+Owu8eU1ga/TkH4gaD7
Kq0ytCKBjmLLAabvW0OrRp9Nw9CN9ODQDNErUmCOeat9OQe28wYRXP9IpIPGNTMZ
QwIDAQAB
-----END PUBLIC KEY-----
```

**Public Key — Boot Partition** (SubjectPublicKeyInfo):

```
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvkweQmnYWmUS0+vqlJoZ
J0oVn7ZW/BZtkA0Dz6lxQLg4JZ47BFlCE1O8NVkvxXKWW1wikwllfXdIAn9DYrMr
SPccbBrqh7mItuPcgDwOkdHDPnI9AhlM1HiNut7ZLHCn3eXSJ7Uf69omPogrq63X
GrJpnCtLplCmQSDw3FgFSKHMrcj3k0JXkYa5OyQYFnOVaExylrYlw9kKi3vy+wYW
nbgiQal/H/V9L588xUJ0sxQp95nxrm3oLJ5rT2SwIpuFEt9JQe+VfVhxMR6CeFO7
zQB8gdbj52XFAnP6qhLbU7+LGt2mxRH0Qvf1OuJjm9DqLAot3wqCuP5O7iVO4Scm
VQIDAQAB
-----END PUBLIC KEY-----
```

---

## 2. X.509 Certificates (i.MX8M HAB Secure Boot)

Found via binwalk in `emmc_dump_lba_16384_131071_115200.raw.log`. 8 certificates (4× redundant copies of 2 unique) at these offsets:

- `0x1098ac` / `0x113eac` / `0x1ca969c` / `0x1cde8cc` — CSF1_1
- `0x109e04` / `0x114404` / `0x1ca9bf4` / `0x1cdee24` — IMG1_1

| Certificate | Subject | Issuer | Valid | Key |
|---|---|---|---|---|
| `cert_csf1_1_sha256_2048.pem` | `CSF1_1_sha256_2048_65537_v3_usr` | `SRK1_sha256_2048_65537_v3_ca` | 2020-08-17 → 2120-07-24 | RSA-2048 |
| `cert_img1_1_sha256_2048.pem` | `IMG1_1_sha256_2048_65537_v3_usr` | `SRK1_sha256_2048_65537_v3_ca` | 2020-08-17 → 2120-07-24 | RSA-2048 |

**HAB chain:** SRK (Super Root Key, CA) → CSF (bootloader commands) / IMG (firmware images)

```
-----BEGIN CERTIFICATE-----
MIIDTDCCAjSgAwIBAgIEEjRWhTANBgkqhkiG9w0BAQsFADAnMSUwIwYDVQQDDBxT
UksxX3NoYTI1Nl8yMDQ4XzY1NTM3X3YzX2NhMCAXDTIwMDgxNzE1MTkxNFoYDzIx
MjAwNzI0MTU1OTE0WjAqMSgwJgYDVQQDDB9DU0YxXzFfc2hhMjU2XzIwNDhfNjU1
MzdfdjNfdXNyMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA9ePWv5Pv
/VSg3OKOL1HdZwEGHVC1vKThy2+NojOVCRrEed6+3LcIttFspS2LvbSWgpwPBE4P
VTVdpbA3u5F4XaPvyFuOdieF5BdhvgdBuOLnvZIl8LlUZX3S4q3GfmEIYgE6CZ3p
kRqw7O0FRym6jIJUTv9DKjmw0SPbAACVFzUwo+mKytRNgioaxCmd/4h5jklXcdCu
KEuUsClf/lqI6LczYnI7+tQGB000WSLtU+zQ7gsb3OFebpzCVfNrRekFsRgP3AaD
jLYplT/OiE1yyA0nmZtgPDuuvbVFmV9KvYJQMXsztJQDVc3S5WHP2MMShiY0A5HU
mNDXRbx2JS+fUQIDAQABo3sweTAJBgNVHRMEAjAAMCwGCWCGSAGG+EIBDQQfFh1P
cGVuU1NMIEdlbmVyYXRlZCBDZXJ0aWZpY2F0ZTAdBgNVHQ4EFgQUlWgFXhl1hD4t
ozx4ML71hYG9aZswHwYDVR0jBBgwFoAUEvgEvHH6Sa+4ZNwvJL5Ss1rJlPwwDQYJ
KoZIhvcNAQELBQADggEBAHaMpt2DNxvTY3PyS+EGI1ktWv6/eAol8ePAq2AxlQXU
KUoFmpkFWzKNYQZTD9SqJvHYF2BnmUGRBE0+xmtFqz3AFvSICQwqDjjTUFtNYms7
NTw3rOpZqdYMvSKHyEwGw/gCPQ0AQhiBLYHX1iTfg0INrXhBfVZAxwy1FtdTrj1k
PccCjJzG0Xyzh53QFyDH1gwhWDz9XC/HLBJEzYdsOuaf7CujT8IOuIv9EOtSQQNk
PDSVRIP4SS8ifs4hv3vRRNqbnV1d5s491Af0OT+Bj+i37lU7L2XKVvoigjPrBexu
+DsKe8FpQBJnnlT6ye9QBwojT8BjmBioNFd2cXG7wkc=
-----END CERTIFICATE-----
```

```
-----BEGIN CERTIFICATE-----
MIIDTDCCAjSgAwIBAgIEEjRWhjANBgkqhkiG9w0BAQsFADAnMSUwIwYDVQQDDBxT
UksxX3NoYTI1Nl8yMDQ4XzY1NTM3X3YzX2NhMCAXDTIwMDgxNzE1MTkxNVoYDzIx
MjAwNzI0MTU1OTE1WjAqMSgwJgYDVQQDDB9JTUcxXzFfc2hhMjU2XzIwNDhfNjU1
MzdfdjNfdXNyMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA0yeMl3wS
VeBkJXMjrg0Cm7yJiU8gp29vdAQzKcsF9EnU+3F8RQNp4Udqdiecyd7z9Ocfv/Gm
NPSINN2sFp/FdIrH7Ph5r39izZCvnst+ui4jZsnwDJ5gfC1oKykqk45vnM3n7fqf
1vFFK31cfoZIzEFuje9NwUYX6w8GyBi04h1MAiRI/oS/efQLjtCjatfzPn9w49bm
MtijklQykEWdIXUoSOrnZ4+4xUZarzu/OmKkIL80NrGx7FB7X7mSQp1HUGITnIvL
J01eDq/qpxNpsBtsiL1DobhoPQ/SF1ysUwXr/ygEUTK74p7OniDpBBTGL8AHqoxv
DkxQrq0u4ILMGQIDAQABo3sweTAJBgNVHRMEAjAAMCwGCWCGSAGG+EIBDQQfFh1P
cGVuU1NMIEdlbmVyYXRlZCBDZXJ0aWZpY2F0ZTAdBgNVHQ4EFgQUInIKs+D6D0GD
eg1r0B/IkGGGBrAwHwYDVR0jBBgwFoAUEvgEvHH6Sa+4ZNwvJL5Ss1rJlPwwDQYJ
KoZIhvcNAQELBQADggEBAEijRnKDBki5F33LzrZXINMthhchbYJ8Jtr+97YFUFyh
+hGCCialboqigYEaaqYofZGnHRxiypS6iQgVCdeHXJEiVc3SgTNoNuu/H3eMIiE9
YTQVz5hcgU3LWKLQo401XdzjGg1PAk3R/vCQP8HdMzlwrvwc9H4BhkT3lqTghbg7
EHHHLHL1oYRMJU2j0fE5HG1url+F4knyR8GWgZNhlhggLZUtuQlnrCH7JK5nIi3y
QkmA9RAAx9WU9lMOFLCBHpt7wn3r4qU8EkKSpOg5trpcBUAfPmFK1z6B4qoHgPrf
I3I6Z9+pv7gCvgPA5z7neIcILKF5ID+kVRN2ojjcVq4=
-----END CERTIFICATE-----
```

---

## 3. Encryption Architecture (CAAM)

The Neato D8 (i.MX8M Nano) uses NXP's CAAM (Cryptographic Acceleration and Assurance Module) for all cryptographic operations. Source: kernel boot log in user partition dump.

### CAAM Hardware

From kernel boot log (`emmc_dump_lba_5521408_999999_115200.raw.log`):

```
caam 30900000.caam: device ID = 0x0a16040100000100 (Era 9)
caam 30900000.caam: job rings = 3, qi = 0, dpaa2 = no
caam algorithms registered in /proc/crypto
caam_jr 30901000.jr0: registering rng-caam
caam 30900000.caam: caam pkc algorithms registered in /proc/crypto
platform caam_sm: blkkey_ex: 2 keystore units available
```

### CAAM Key Store — Keys at Boot

The kernel logs show clear keys, black keys (hardware-encrypted), and blob-wrapped keys loaded during boot. The clear keys are sequential test patterns (`00 01 02 03 04 0f 06 07 ...`). The black keys are the actual hardware-encrypted keys.

| Key Size | Clear Key (hex) | Black Key (hex) |
|----------|-----------------|------------------|
| 64-bit | `[0000] 00 01 02 03 04 0f 06 07` | `[0000] 39 36 e5 2a df dc 49 f7 [0008] a5 33 4b 43 bb 7b 27 07` |
| 128-bit | `[0000] 00 01 02 03 04 0f 06 07 [0008] 08 09 0a 0b 0c 0d 0e 0f` | `[0000] f8 78 d3 55 8c d3 fd 2e [0008] 45 5d e2 9e 28 7f fb 65` |
| 192-bit | `[0000] 00 01 ... [0016] 10 11 12 13 14 15 16 17` | `[0000] 34 ff ... [0024] 90 73 19 be 28 cd 9d 9d` |
| 256-bit | `[0000] 00 01 ... [0008] 08 09 0a 0b 0c 0d 0e 0f` | (logged but truncated) |

The CAAM also reports blob-wrapped and restored keys:

```
platform caam_sm: 64-bit black key in blob:
platform caam_sm: 128-bit black key in blob:
platform caam_sm: 192-bit black key in blob:
platform caam_sm: 256-bit black key in blob:
platform caam_sm: restored 64-bit black key:
platform caam_sm: restored 128-bit black key:
platform caam_sm: restored 192-bit black key:
platform caam_sm: restored 256-bit black key:
```

The master key (OTPMK) is burned into i.MX8MN eFuses and is only readable by CAAM hardware. Black keys are encrypted with the OTPMK and cannot be extracted by software.

### CAAM Crypto Algorithms Registered

From kernel boot log:

```
caam algorithms registered in /proc/crypto
caam pkc algorithms registered in /proc/crypto
lib80211_crypt: registered algorithm 'NULL'
lib80211_crypt: registered algorithm 'WEP'
lib80211_crypt: registered algorithm 'CCMP'
lib80211_crypt: registered algorithm 'TKIP'
Key type dns_resolver registered
Key type caam_tk registered
```

---

## 4. Encrypted Boot Chain

Source: U-Boot environment variables extracted from `emmc_dump_lba_0_2200_115200.raw.log`.

### U-Boot Boot Sequence (Encrypted)

All files on the FAT partition (kernel1/kernel2) are CAAM-encrypted (`.enc` suffix). U-Boot loads them and decrypts via `file_decrypt`.

**Load sequence** (from `mmcboot` U-Boot env var):

```
1. loadkeyblob  → fatload key_blob.enc       → 0x45000000
2. loadimage    → fatload Image.enc           → file_decrypt → 0x40480000
3. loadfdt      → fatload *.dtb.enc           → file_decrypt → 0x43000000
4. loadinitrd   → fatload initrd.uImage.enc   → file_decrypt → 0x43800000
5. loadswuk     → fatload swu-pubk.pem.enc    → file_decrypt → 0x43100000 (if HAB version exists)
6. loadsig      → fatload *.sig.enc            → file_decrypt (if HAB version exists)
7. booti ${loadaddr} ${initrd_addr} ${fdt_addr}
```

### Key Addresses (U-Boot env)

| Variable | Address | Purpose |
|----------|---------|---------|
| `loadaddr` | `0x40480000` | Kernel image (decrypted) |
| `fdt_addr` | `0x43000000` | Device tree (decrypted) |
| `initrd_addr` | `0x43800000` | Initramfs (decrypted) |
| `enc_file_addr` | `0x46000000` | Temporary encrypted file buffer |
| `keyblob_addr` | `0x45000000` | CAAM key blob |
| `swuk_addr` | `0x43100000` | SWU public key (decrypted) |

### Encrypted Files on FAT Partition

| File | Purpose |
|------|---------|
| `key_blob.enc` | CAAM decryption key blob |
| `Image.enc` | Linux kernel |
| `emcraft-imx8mn-ddr4-som.dtb.enc` | Device tree (primary) |
| `neato-prime.dtb.enc` | Device tree variant |
| `neato-frost.dtb.enc` | Device tree variant |
| `initrd.uImage.enc` | Initramfs |
| `swu-pubk.pem.enc` | Software update public key |
| `*.sig.enc` | Kernel/DTB/initrd signatures |

### `file_decrypt` Command

Custom U-Boot command. Syntax: `file_decrypt <keyblob_addr> <keyblob_size> <enc_addr> <dec_addr> <size>`

**Tested behavior:** Without a valid CAAM key blob loaded, `file_decrypt` returns "Okay" but copies input to output unchanged (no-op). With a valid key blob loaded from the FAT partition, actual decryption occurs — proven by the valid ARM64 kernel and decompressible initrd found in RAM dumps.

### Root Filesystem Encryption (rfs1/rfs2)

The root filesystems (`rfs1` = mmcblk2p3, `rfs2` = mmcblk2p4) are encrypted at block device level. Partial dumps of rfs2 show **8.00 bits/byte entropy** — consistent with AES-256 ciphertext. No ext4 superblock magic (0xEF53) found.

**dm-crypt configuration** (from `unlock-rootfs.sh` in initramfs):

```sh
dmsetup -v create encrypted --table "0 $(blockdev --getsz $root_part) crypt capi:tk(cbc(aes))-plain :36:logon:logkey: 0 $root_part 0 1 sector_size:512"
```

| Parameter | Value |
|-----------|-------|
| Target | `crypt` |
| Cipher | `capi:tk(cbc(aes))-plain` (CAAM token-based AES-CBC, plain IV) |
| Key offset | `:36` (byte 36 in the key blob, after 20-byte header + 16 bytes metadata) |
| Key type | `logon` (kernel keyring reference) |
| Key name | `logkey:` |
| Sector size | 512 bytes |

**Root FS unlock sequence** (from `unlock-rootfs.sh`):

```
1. fw_printenv boot2_active → determine A/B partition set
2. Mount boot partition (kernel1 or kernel2 FAT)
3. Convert fs_key_blob.enc if old hex format (kernel 4.14 compatibility)
4. caam-keygen import /mnt/fs_key_blob.enc randomkey
5. cat /data/caam/randomkey | keyctl padd logon logkey: @s
6. Unmount boot partition
7. dmsetup create encrypted → /dev/mapper/encrypted
8. switch_root to real root filesystem
```

**Key blob format** (binary, "Ogat" magic):

```
Offset  Size  Content
0x00    4     Magic: "Ogat" (0x4f676154)
0x04    4     Padding/reserved (0x00000000)
0x08    4     Version (1, LE)
0x0C    4     Flags (0x10)
0x10    4     Blob length (0x4c = 76 bytes, LE)
0x14    16    IV/metadata
0x24    32    Encrypted key material (AES-256)
0x44    12    Padding/end marker
Total:  76 bytes
```

Old format (kernel 4.14): hex string with `:hex:` prefix, auto-converted on first boot.

### `user` Partition

Not encrypted. Plain ext4 filesystem. UUID: `57f8f4bc-abf4-655f-bf67-946fc0f9f25b`.

---

## 5. SWU Firmware Update

### SWU File Format

The Neato D8 uses **SWUpdate** (sbabic/swupdate) for firmware updates. SWU files are cpio archives containing a `sw-description` manifest and firmware artifacts.

**Downloaded SWU:** `Neato_1.7.0-2933.swu` (158 MB)

```
File: OpenSSL enc'd data with salted password (AES-256-CBC)
Header: "Salted__" + 8-byte salt
Salt: 1eacf67ef2432bc5
```

The SWU is encrypted with `openssl enc -aes-256-cbc`. This is the symmetric encryption mode documented in swupdate (CONFIG_ENCRYPTED_IMAGES). The AES key is a separate secret — not the same as the CAAM hardware keys.

### SWUpdate Daemon

From user partition kernel log:

```
Jan 14 11:12:40 Neato-Robot user.info swupdate: SUCCESS (null)
```

From manufacturing test log:

```
CSV,AppSWUpdateTest_Production,Start,0,2021-04-12 18:02:39.950
CSV,AppSWUpdateTest_Production,End,1,2021-04-12 18:02:42.193
```

### SWU Public Key

U-Boot loads `swu-pubk.pem.enc` from the FAT partition during boot and decrypts it via CAAM. This is the swupdate signature verification public key (address `0x43100000`).

From U-Boot env:

```
swuk_file=swu-pubk.pem.enc
swuk_addr=0x43100000
loadswuk=if hab_version; then fatload mmc ${mmcdev}:${mmcpart} ${enc_file_addr} ${swuk_file} && file_decrypt ${keyblob_addr} ${keyblob_size} ${enc_file_addr} ${swuk_addr} ${filesize}; else echo skip swuk; fi;
```

The SWU public key is only loaded if a HAB version exists — meaning it is tied to the secure boot (HAB) feature.

### Kernel Modules

Kernel config (`ikconfig.txt` from extracted vmlinux):

- Linux version: `5.4.47-rt28-1.7.0-2933_10060147_cfae4f98`
- CONFIG_ARM64_CRYPTO=y
- CONFIG_CRYPTO_SHA256_ARM64=y
- CONFIG_CRYPTO_AES_ARM64=y
- CONFIG_CRYPTO_AES_ARM64_CE=y (CAAM Cryptographic Extensions)
- No CONFIG_SWUPDATE or CONFIG_OTA options in kernel config — swupdate runs as a userspace daemon on the encrypted root filesystem

---

## 6. eMMC Partition Layout

| # | Name | Start LBA | End LBA | Size | Encryption |
|---|------|-----------|---------|------|------------|
| — | hidden | 0x0000 | 0x3FFF | 8 MB | N/A (bootloader) |
| 1 | kernel1 | 0x4000 | 0x23FFF | 64 MB | CAAM-encrypted FAT files |
| 2 | kernel2 | 0x24000 | 0x43FFF | 64 MB | CAAM-encrypted FAT files (A/B) |
| 3 | rfs1 | 0x44000 | 0x2C3FFF | 1.25 GB | dm-crypt (AES-256-CBC via CAAM) |
| 4 | rfs2 | 0x2C4000 | 0x543FFF | 1.25 GB | dm-crypt (AES-256-CBC via CAAM) (A/B) |
| 5 | user | 0x544000 | 0x71FFFD | 952 MB | Unencrypted ext4 |

---

## 7. Firmware Versions

| Component | Version | Build Date |
|-----------|---------|------------|
| SPL | `2020.04-1.7.0-2749_08020951_cfae4f98` | Aug 02 2022 |
| U-Boot | `2020.04-1.7.0-2749_08020951_cfae4f98` | Aug 02 2022 |
| TF-A (BL31) | `v2.2(release):rel_imx_5.4.47_2.2.0` | Nov 03 2021 |
| OP-TEE OS | (identified by source paths) | — |
| Linux kernel | `5.4.47-rt28-1.7.0-2933_10060147_cfae4f98` | Oct 06 2022 |
| SWU firmware | `1.7.0-2933` | — |
| Initramfs | "Lego Startup Initrd v0.1" | Oct 06 2022 |

---

## 8. Extraction Notes

### PEM Keys

Keys extracted from raw eMMC dump files (UART log format) using `grep` for PEM markers. Dump files contained ANSI escape sequences and UART timestamps prepended to PEM data. Stripped during extraction. Base64 payload decoded to DER and re-encoded as clean PEM via OpenSSL.

### X.509 Certificates

Found via `binwalk` signature scan. Certificates are in DER format, embedded in boot partition data. Extracted by searching for ASN.1 SEQUENCE magic bytes (`0x30 0x82 0x03 4c`) and extracting 4+844 bytes per certificate.

### Additional binwalk Findings

- **User partition** (LBA 0x544000, 0x55F4A0): Multiple `mcrypt 2.2` encrypted segments (Blowfish-448, CBC, MD5/SHA-1 key derivation)
- **Boot partition**: FDT/DTB, PKCS#7 signatures, Android bootimg headers, SHA256 constants, DES SP1/SP2 tables
- **RAM dump** (0x40000000): Linux kernel ARM64, ELF binaries, gzip data
