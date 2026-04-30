#!/bin/bash
# emmc-dump-all.sh - Fast eMMC dump via UART2 (flat bootcmd)
# Usage: ./emmc-dump-all.sh [start_block] [num_blocks] [baudrate]
#
# Uses gen-bootcmd-flat.py for on-device 32-byte chunks.
# Baudrate is set via uart-setup.sh (must be in uart/ subdirectory).

SCRIPTDIR="$(cd "$(dirname "$0")" && pwd)"

START_BLOCK_DEC="${1:-0}"
NUM_BLOCKS="${2:-$((7759872 / 512))}"
BAUD="${3:-115200}"

START_BLOCK_HEX=$(printf '%x' "$START_BLOCK_DEC")
LOGFILE="$SCRIPTDIR/emmc_dump_lba_${START_BLOCK_DEC}_${NUM_BLOCKS}_${BAUD}.raw.log"
OUTFILE="$SCRIPTDIR/emmc_dump_lba_${START_BLOCK_DEC}_${NUM_BLOCKS}_${BAUD}.dd"
RAM_BASE=0x42000000
BYTES_PER_RUN=32
RUNS_PER_BLOCK=$((512 / BYTES_PER_RUN))  # 16

TOTAL_BYTES=$((NUM_BLOCKS * 512))
TOTAL_MB=$((TOTAL_BYTES / 1048576))

echo "=========================================="
echo "  eMMC Fast Dump (flat bootcmd)"
echo "=========================================="
echo "  Start block (dec):  $START_BLOCK_DEC"
echo "  Start block (hex):  0x$START_BLOCK_HEX"
echo "  Num blocks:   $NUM_BLOCKS"
echo "  Total size:   $TOTAL_BYTES bytes (~${TOTAL_MB}MB)"
echo "  Bytes/run:    $BYTES_PER_RUN ($RUNS_PER_BLOCK runs/block)"
echo "  Baudrate:     $BAUD"
echo "  Log file:     $LOGFILE"
echo "  Output:       $OUTFILE"
echo "=========================================="
echo ""

# Set UART baudrate via uart-setup.sh
#echo "Setting UART to ${BAUD} baud..."
#"$SCRIPTDIR/uart/uart-setup.sh" $BAUD --exec
#echo ""

killall cat

# Start logger
echo "Starting logger..."
stty -F /dev/ttyUSB0 $BAUD raw -echo
cat /dev/ttyUSB0 >> "$LOGFILE" </dev/null &
LOGGER_PID=$!
echo $LOGGER_PID > "$SCRIPTDIR/uart/ttyusb0.pid"

START_TIME=$(date +%s)
LAST_PRINT=$START_TIME
ERRORS=0

echo "[dump] Starting block loop..."

for ((blk_dec=$START_BLOCK_DEC; blk_dec<START_BLOCK_DEC+NUM_BLOCKS; blk_dec++)); do
    NOW=$(date +%s)
    ELAPSED=$((NOW - START_TIME))
    LAST_DELTA=$((NOW - LAST_PRINT))

    # Progress every 10 seconds
    if (( LAST_DELTA >= 10 || blk == START_BLOCK )); then
        DONE=$((blk_dec - START_BLOCK_DEC))
        BYTES_DONE=$((DONE * 512))
        if (( ELAPSED > 0 && DONE > 0 )); then
            SPEED=$((BYTES_DONE / ELAPSED))
        else
            SPEED=0
        fi
        BLK_HEX=$(printf '%x' $blk_dec)
        echo -ne "\r[dump] Block $blk_dec (0x$BLK_HEX) / $((START_BLOCK_DEC+NUM_BLOCKS-1)) | ${BYTES_DONE}/${TOTAL_BYTES} B | ${SPEED} B/s | ${ELAPSED}s | err: ${ERRORS}   "
        LAST_PRINT=$NOW
    fi

    # mmc read -> RAM
    BLK_HEX=$(printf '%x' $blk_dec)
    read_out=$("$SCRIPTDIR/uuu" FB: ucmd mmc read $RAM_BASE 0x$BLK_HEX 1 2>&1)
    if ! echo "$read_out" | grep -q "Okay"; then
        ((ERRORS++))
        continue
    fi

    # 16 runs per block, each 32 bytes
    for ((run=0; run<RUNS_PER_BLOCK; run++)); do
        OFFSET=$((run * BYTES_PER_RUN))
        ADDR=$(printf "0x%08X" $((RAM_BASE + OFFSET)))

        BOOTCMD=$(python3 "$SCRIPTDIR/gen-bootcmd-flat.py" $BYTES_PER_RUN $ADDR 0)

        setenv_out=$("$SCRIPTDIR/uuu" FB: ucmd setenv bootcmd $BOOTCMD \;run bootcmd 2>&1)
        if ! echo "$setenv_out" | grep -q "Okay"; then
            ((ERRORS++))
            break
        fi

#        run_out=$("$SCRIPTDIR/uuu" FB: ucmd run bootcmd 2>&1)
#        if ! echo "$run_out" | grep -q "Okay"; then
#            ((ERRORS++))
#            break
#       fi
#	sleep 0.5
    done
done

echo ""
END_TIME=$(date +%s)
TOTAL_SEC=$((END_TIME - START_TIME))
echo ""
echo "  Dump finished in ${TOTAL_SEC}s"
if [ $ERRORS -gt 0 ]; then
    echo "  WARNING: ${ERRORS} errors!"
fi
echo ""

# Stop logger
echo "Stopping logger..."
LOGGER_PID=$(ps aux | grep 'cat.*ttyUSB0' | grep -v grep | awk '{print $2}')
if [ -n "$LOGGER_PID" ]; then
    kill $LOGGER_PID 2>/dev/null
    echo "  Killed logger PID(s): $LOGGER_PID"
else
    echo "  No logger process found"
fi
rm -f "$SCRIPTDIR/uart/ttyusb0.pid"

# Extract raw bytes
echo "Extracting $TOTAL_BYTES bytes from log..."
LOGSIZE=$(wc -c < "$LOGFILE")
echo "  Log size: $LOGSIZE bytes (expected: $TOTAL_BYTES)"
tail -c $TOTAL_BYTES "$LOGFILE" > "$OUTFILE"

ACTUAL=$(wc -c < "$OUTFILE")
echo ""
echo "=========================================="
echo "  Output: $OUTFILE ($ACTUAL bytes)"
echo "  Errors: ${ERRORS}"
echo "=========================================="
xxd -l 64 "$OUTFILE"
