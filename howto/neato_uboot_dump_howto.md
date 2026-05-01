
# Requirements duming EMMC neato gen4
 - Neato gen4 D8/D9/D10 with RGB
 - USB C cable
 - UART 3.3V to USB adapter
 - host pc with linux and 2x usb
 - uuu from https://github.com/nxp-imx/mfgtools
 
# Check communication USB-C
 - Plug in USB-C to robot and host pc
 - check if uuu can see robot (run as root): 
```
8# ./uuu -lsusb
uuu (Universal Update Utility) for nxp imx chips -- libuuu_1.5.243-0-g230f1b1

Connected Known USB Devices
        Path     Chip    Pro     Vid     Pid     BcdVersion      Serial_no
        ====================================================================
        1:84             FB:     0x0525 0xA4A5   0x0221  <here serial>
```
 - if there is no serial, the communication is not workin
  -  check drivers (windows) or run with root (linux)


# using uuu with fastboot protocol
 - robot uboot is running fastboot protocol
 - basic command like this:
```
./uuu FB: ucmd echo blabla
uuu (Universal Update Utility) for nxp imx chips -- libuuu_1.5.243-0-g230f1b1

Success 0    Failure 0


1:84         1/ 1 [                                      ] FB: ucmd echo blabla
Okay
```
 - only feedback we get is `Okay` or `Error` => so we are essentially blind
 - exception: `uuu -V FB: getvar all`
   - this return all vars from fastboot (but only when `-V`)
   - same as `fastboot getvar all`
   - maybe this calls fastboot output function, not uboot?

# connecting robot gen4 to UART-USB-Adapter
  - remove bumper cover (just wiggle)
  - connection see image. notice crossed RX and TX
(gen4_bumper_uart.png)

# testing UART to USB feedback :
 - now fire up a terminal on host pc pointing to the uart-usb-adapter with 115200
 - reboot robot, something `BL31 bootloader blabla` comes up -> good
  
# testing UART to USB feedback path manually
 - as we are blind (see above), only feedback is the UART2 TX path
 - UART2 base sits at `0x30890000`
 - first: to enable TX we need to do:
   - `uuu FB: ucmd mw.l 0x30384b00 3` (enable clock for URAT2)
   - `uuu FB: ucmd mw.l 0x30330008 0` (TX pin mux set)
 - now fire up a terminal on host pc pointing to the uart-usb-adapter with 115200
 - to send a test 'A' via UART2 via uuu fastboot comand:
   - `uuu FB: ucmd mw.b 0x30890040 0x41` (memory-write byte 'A' to UART2 TX register)
   - terminal now should show 'A'

# dumping emmc manunally
Currently this is the only way:
 - enable UART2 tx
 - copy block from emmc to RAM: `uuu FB: ucmd mmc read <target> <blk#> <cnt>`
   - caution: use only 0x hex addresses
   - example: `uuu FB: ucmd mmc read 0x42000000 0x0 1` (copy 1 block (512 bytes) from 0x0 to hopefully unused RAM at 0x42000000)
 - copy one byte from this RAM to UART2 TX:
   - `uuu FB: ucmd cp.b 0x42000000 0x30890040 1`
   - can copy only one (1!) byte because TX register is just 8 bit
   - also fifo is 32 bytes, but sometimes scrambles (prins first fifo-item at last wtf)
 - repeat TX liek 512 times the copy next block from emmc to RAM and repeat

# dumping emmc with base script
 - needs:
   - `emmc-dump-all.sh` and `gen-bootcmd-flat.py`
 - Usage:
   - `Usage: ./emmc-dump-all.sh [start_block] [num_blocks] [baudrate]`
 - Example:
   - `./emmc-dump-all.sh 0x0 2048 115200`
     - Dumps emmc from 0x with length 2048 blocks so 1mb 
     - should be something like `2026-04-30_emmc_lba_0_2200_try1.dd`

