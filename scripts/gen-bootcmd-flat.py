#!/usr/bin/env python3
"""Generate U-Boot bootcmd for dumping N bytes from memory via UART2 (no for-loop)
Uses cp.b for byte-wise memory-to-UART copy.
Optional sleep after all bytes for FIFO drain."""
import sys

n = int(sys.argv[1]) if len(sys.argv) > 1 else 32
addr_start = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith('-') else "0x42000000"
sleep_after = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] != "0" else None

if addr_start.startswith("0x") or addr_start.startswith("0X"):
    addr_start = int(addr_start, 16)
else:
    addr_start = int(addr_start)

parts = []
for i in range(n):
    addr = addr_start +  i
    parts.append(f"cp.b 0x{addr:08X} 0x30890040 1")

# Move first cp.b to end (workaround: first UART write after idle emits stale byte)
if parts:
    parts.insert(0,parts.pop(n-1))

if sleep_after:
    parts.append(f"sleep {sleep_after}")

bootcmd = "; ".join(parts)
print(bootcmd)
