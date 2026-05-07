# Streamer Plan – Neato D8 eMMC Dump via UART2

## Status: PoC Phase

First, a Proof of Concept: small dump (e.g. 1 block = 512 bytes), verify data, test pacing. Only scale to 10MB blocks once the PoC runs clean.

## Mechanism

### On the Device (U-Boot bootcmd via uuu)

CBSIZE ≈ 2054 chars → complete loop + 10MB logic doesn't fit in a single bootcmd.
Solution: set up sub-commands via `setenv`, call only `run` in the bootcmd.

#### Sub-Commands (once via uuu, before the loop)

Each logical unit is its own `setenv` → short, testable, interchangeable.
`_cp` is the central iteration — TRDY logic can be plugged in here
without changing `_blk` or `_next`.

```
# Primitives (individual actions)
uuu FB: ucmd setenv _wr 'cp.b ${_addr} 0x30890040 1'
uuu FB: ucmd setenv _adv 'setexpr _addr ${_addr} + 1\; setexpr _i ${_i} + 1'
uuu FB: ucmd setenv _trdy_poll 'setexpr _usr1 \*0x30890094\; setexpr _trdy $_usr1 \& 0x2000\; while test $_trdy -eq 0\; do setexpr _usr1 \*0x30890094\; setexpr _trdy $_usr1 \& 0x2000\; done'
uuu FB: ucmd setenv _trdy_chk 'setexpr _usr1 \*0x30890094\; setexpr _trdy $_usr1 \& 0x2000\; if test $_trdy -ne 0\; then run _wr\; run _adv\; else run _trdy_poll\; run _wr\; run _adv\; fi'

# Iteration strategies (selectable)
uuu FB: ucmd setenv _cp_blind 'run _wr\; run _adv\; sleep 0.01'
uuu FB: ucmd setenv _cp_chk   'run _trdy_chk\; sleep 0.01'
uuu FB: ucmd setenv _cp_poll  'run _trdy_poll\; run _wr\; run _adv'

# Block control
uuu FB: ucmd setenv _blk 'mmc read 0x42000000 ${_start} ${_sectors}\; setenv _i 0\; setenv _addr 0x42000000\; while test ${_i} -lt ${_iters}\; do run _cp\; done'
uuu FB: ucmd setenv _next 'setexpr _start ${_start} + ${_sectors}\; setenv bootcmd "run _blk"\; saveenv\; run bootcmd'
```

| Env Var | Purpose | Length |
|---------|---------|--------|
| `_sectors` | sectors per mmc read (e.g. 20480 for 10MB) | 1 line |
| `_iters` | iterations per block (e.g. 10485760 for 10MB at 1B/iter) | 1 line |
| `_start` | current start sector | runtime |
| `_addr` | RAM pointer (incremented) | runtime |
| `_i` | iteration counter | runtime |
| `_usr1` | USR1 value (TRDY check) | runtime |
| `_trdy` | TRDY mask result | runtime |
| `_wr` | RAM → UART TX write (cp.b count=1) | 1 command |
| `_adv` | increment pointer + counter | 2 commands |
| `_trdy_poll` | wait until TRDY=1 | ~3 commands |
| `_trdy_chk` | check once, if not ready → poll | ~5 commands |
| `_cp` | **selectable iteration strategy** | see below |
| `_cp_blind` | write without TRDY + sleep 0.01 | 3 runs |
| `_cp_chk` | TRDY check + sleep 0.01 (fallback: poll) | 4 runs |
| `_cp_poll` | TRDY poll without sleep | 3 runs |
| `_blk` | dump one block (mmc read + while) | 1 mmc read + while |
| `_next` | next block (offset + saveenv + run) | 4 commands |

**Switching strategy:**
```
uuu FB: ucmd setenv _cp 'run _cp_blind'   # blind + sleep (safe, slow)
uuu FB: ucmd setenv _cp 'run _cp_chk'     # TRDY check + sleep (robust)
uuu FB: ucmd setenv _cp 'run _cp_poll'    # TRDY poll without sleep (fast?)
```

#### Runtime Configuration

```
uuu FB: ucmd setenv _sectors 20480
uuu FB: ucmd setenv _iters 10485760
```

With unrolled `_wr16`: `_iters = 10485760 / 16 = 655360`

#### Starting

```
uuu FB: ucmd setenv _start 0 \; setenv _cp 'run _cp_blind' \; setenv bootcmd 'run _blk' \; saveenv \; run bootcmd
```

- Stale-byte workaround: optionally dummy `mw.l 0x30890040 0x00` before the loop
- Escaping: `;` → `\;` for bash → uuu → U-Boot
- `_cp` strategy can be switched at runtime: `uuu FB: ucmd setenv _cp 'run _cp_poll'`
  (active on next `run _blk` automatically — or directly `run _cp` in a running loop?)

#### cp.b on MMIO — Clarification

`cp.b src 0x30890040 N` writes N bytes **starting at** address 0x30890040, not N× into the same register.
Since 0x30890040 is an 8-bit UTXD register without an array, only **count=1** can be used.

**Consequence:** `_chunk` is always 1. Each iteration writes exactly 1 byte.

For multiple bytes per iteration: unrolled `_wrN` (see Performance Optimization below).

#### Performance Optimization: Unrolled Writes

Instead of 1 byte per iteration (3 commands: cp.b + setexpr + setexpr), we can
unroll N bytes in a `_wrN` sub-command — less U-Boot loop overhead:

```
setenv _wr16 'setexpr _a ${_addr}\; cp.b ${_a} 0x30890040 1\; setexpr _a ${_a} + 1\; cp.b ${_a} 0x30890040 1\; ...(16x)...\; setexpr _addr ${_addr} + 16\; setexpr _i ${_i} + 16'
```

- 16 bytes per `_wr16` call: ~6 commands × 16 = 96 commands, ~900 chars → fits in CBSIZE
- While loop needs `_iters = BLOCK_SIZE / 16` = 655,360 for 10MB
- Per iteration: ~5ms U-Boot overhead (no sleep needed, FIFO has room)
- **~55min per 10MB block** (vs. 33h with 1-byte + sleep 0.01)

| Unroll | Commands/iter | Chars | Iters/10MB | Est. time/block |
|--------|--------------|-------|------------|-----------------|
| 1      | 3            | ~60   | 10,485,760 | ~33h (sleep 0.01) |
| 8      | ~50          | ~450  | 1,310,720  | ~1.8h             |
| 16     | ~96          | ~900  | 655,360    | ~55min            |
| 32     | ~192         | ~1800 | 327,680    | ~27min (CBSIZE limit!) |

**Note:** Time estimates are rough (assumed 5ms/iter U-Boot overhead).
Must be measured with PoC.

**ARM64 Stub Alternative:** For maximum performance: ARM64 code directly in RAM
(strb loop, no U-Boot overhead). Potentially 10-100× faster.
See `uboot_umleiten/gd-read.md` for the stub approach.

#### Calculation
- 1 byte per iteration (MMIO constraint: cp.b count=1)
- `_cp_blind` (sleep 0.01): ~12ms/iter → 10MB in ~35h → not practical
- `_wr16` unrolled (no sleep, 16B/iter): ~5ms/iter → 10MB in ~55min
- `_wr32` unrolled (CBSIZE limit): ~5ms/iter → 10MB in ~27min
- Full eMMC (~375 blocks × 55min) = **~344 hours (~14 days)**
- At 500k baud (FIFO drains faster, less overhead per byte): possibly **~7-10 days**
- **ARM64 stub** (no U-Boot overhead): potentially **~1-2 days**

### On the Host (Python + cat)

- `stty -F /dev/ttyUSB0 115200 raw -echo`
- `cat /dev/ttyUSB0 > block_NNN.bin </dev/null &`
- `uuu FB: ucmd mmc read ... \; FB: ucmd setenv bootcmd 'while ...' \; FB: ucmd run bootcmd`
- Monitor: poll file size, calculate rate, ETA

### PoC: FIFO / Pacing Test

Test different sleep values (0, 0.005, 0.01, 0.1) with 1 block (512 bytes = 16 iterations of 32 bytes):

1. Load block 0 into RAM via mmc read
2. Dump with while-loop at sleep=X
3. Compare cat output with known content (e.g. GPT header at sector 0)
4. If data is correct → minimize sleep until breaking point
5. Document result in plan

**Expectation:** `sleep 0.01` should be safe. `sleep 0` likely causes data loss.

## Directory Structure

```
projects/2026-04-neato-d8/stream/
├── plan.md              (this file)
├── stream.py            (main script)
├── done/                (completed blocks)
└── logs/                (stream_YYYYMMDD_HHMMSS.log)
```

## Procedure (stream.py)

### Configuration
```python
BLOCK_SIZE      = 10 * 1024 * 1024   # 10MB
CHUNK_SIZE      = 32                 # bytes per cp.b
SLEEP_SECS      = 0.01               # pacing (PoC: test)
UART_PORT       = '/dev/ttyUSB0'
BAUDRATE        = 115200
RAM_ADDR        = '0x42000000'
UART_TX_REG     = '0x30890040'
SECTOR_SIZE     = 512
SECTORS_PER_BLK = BLOCK_SIZE // SECTOR_SIZE  # 20480
ITERATIONS      = BLOCK_SIZE // CHUNK_SIZE   # 327680
DUMP_DIR        = 'done/'
LOG_DIR         = 'logs/'
```

### Phase 1: UART Preparation
- `killall cat`
- `stty -F /dev/ttyUSB0 115200 raw -echo`

### Phase 2: Determine Offset (Interruptibility)
- Scan `done/` for `block_*.bin`
- Highest block number + 1 = current block
- Alternatively: derive block number from directory contents

### Phase 3: Per Block
1. **Create block file:** `done/block_NNN.bin`
2. **Start cat:** `subprocess.Popen(['cat', UART_PORT], stdout=open(blockfile, 'wb'), stdin=subprocess.DEVNULL)`
3. **mmc read via uuu:** `uuu FB: ucmd mmc read 0x42000000 <start_sector> 20480`
4. **While-loop bootcmd via uuu:**
   ```
   uuu FB: ucmd setenv i 0 \; setenv addr 0x42000000 \; setenv bootcmd 'while test $i -lt 327680\; do cp.b ${addr} 0x30890040 32\; setexpr addr ${addr} + 32\; setexpr i $i + 1\; sleep 0.01\; done' \; run bootcmd
   ```
5. **Monitor:** Poll file size every 1s
   - Calculate bytes/s
   - Remaining time: (10MB - done_bytes) / rate
   - Console + Log: `[block NNN] 5.2MB / 10MB | 1.1KB/s | ETA: 72min`
6. **Done:** When 10MB reached → kill cat, next block
7. **Timeout:** If >5min no growth → kill cat, retry block (max 3 retries)

### Phase 4: End
- When device only sends 00 (or rate==0 across multiple blocks) → dump complete
- Concatenate all `done/block_*.bin` → `emmc_full_dump.bin`
- Cleanup

### Logging
- One log file per run: `logs/stream_YYYYMMDD_HHMMSS.log`
- Contains: start/end, block number, size, rate, errors, retries
- Parallel console output (prints)

### Signal Handling (Ctrl+C)
- Kill cat process
- Current block is restarted on next run (don't delete partial file)
- Clean shutdown

## TRDY Check — Transmitter Ready Before UART Write

### Background

Previously, `_cp` blindly wrote `cp.b 32` to UART2 TX. When the TX FIFO (32 bytes) is full, data is lost. The i.MX8M UART has a TRDY flag (Transmitter Ready, bit 13 in USR1) that indicates whether the FIFO has space.

### Register Info

| Register | Address | Width | Read Safety | Name |
|----------|---------|-------|-------------|------|
| UART2_USR1 | `0x30890094` | 32-bit | ⚠️ untested (RM: offset 0x94 = USR1) | UART Status Register 1 |

- **TRDY = bit 13** → mask: `0x2000`
- Address confirmed from i.MX8MN Reference Manual (Base + 0x94 = USR1)
- ⚠️ **Read safety untested** — `setexpr` (default `.l`) on MMIO registers can have side effects. Must be tested live.

### Iteration Strategies (as `_cp_*` env vars)

See sub-commands above — three strategies are predefined as `_cp_blind`, `_cp_chk`, `_cp_poll`.

| Strategy | TRDY? | Sleep | Speed | Risk |
|----------|-------|-------|-------|------|
| `_cp_blind` | No | 0.01 | ~800 B/s @ 115200 | FIFO overflow possible |
| `_cp_chk` | Check + fallback poll | 0.01 | ~800 B/s | Robust, slight overhead |
| `_cp_poll` | Poll loop | No | ??? (test!) | No sleep, but U-Boot overhead per poll |

**Recommendation:** Start with `_cp_blind` (proven), then test `_cp_chk` for robustness.
`_cp_poll` only if sleep overhead is measurable and TRDY read works reliably.

### TRDY Read Safety

- **Prerequisite:** `setexpr *0x30890094` must be tested live
  - `md` on UART2 range resets — but `setexpr` on a single register?
  - Test: `uuu FB: ucmd setexpr _usr1 \*0x30890094` → device still alive?
  - If yes: send `_usr1` value via UART2 TX: `uuu FB: ucmd mw.b 0x30890040 ${_usr1}`
  - Expectation: TRDY=1 (bit 13 = 0x20 in byte), since UART is idle

### cp.b on MMIO — Critical Question

`cp.b ${_addr} 0x30890040 ${_chunk}` with `_chunk=32`:
- **Best case:** U-Boot's `cp.b` writes 32× into the same 8-bit MMIO register → 32 bytes into TX FIFO
- **Worst case:** `cp.b` increments the destination address → bytes 2-32 land at 0x30890041+ (undefined)
- **Decision:** Live test required! If `cp.b 32` doesn't work:
  - Fallback: `_chunk=1` + double `_iters` (byte-by-byte, ×32 slower)
  - Or: unrolled 32× `mw.b` in `_wr` (check CBSIZE limit)

### Open Questions (PoC)

- [ ] **Test `setexpr *0x30890094`** — is USR1 read safe? Does it freeze? Is the value plausible?
- [ ] **`cp.b ${_addr} 0x30890040 32` on MMIO** — does it write 32× into the same register or 32 bytes from that address? (critical!)
- [ ] **TRDY behavior** — is TRDY normally 1 for idle UART + sleep 0.01?
- [ ] **`_cp_poll` performance** — U-Boot poll overhead measurable vs. sleep 0.01?
- [ ] **Stale-byte workaround** — needed for while-loop? (so far only for unrolled bootcmd)
- [ ] **Escape syntax** — `${_addr}`, `${_chunk}` in setenv strings correctly escaped for bash → uuu → U-Boot?
- [ ] **End detection** — how to determine eMMC is fully read?

## PoC Sequence

1. `setexpr *0x30890094` → survives? → send value via UART2
2. `cp.b ${addr} 0x30890040 32` with known RAM content → check host output (32 correct bytes?)
3. If (2) ok: `_cp_blind` with 1 sector (512B = 16 iters) → compare with known LBA 0 content
4. If (3) ok: test `_cp_chk` / `_cp_poll` → observe TRDY behavior
5. Minimize sleep (0.01 → 0.005 → 0) until breaking point
6. Increase baud rate to 500k → repeat 3-5
```
