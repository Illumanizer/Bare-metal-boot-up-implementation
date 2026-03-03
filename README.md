# STM32F4 Bare-Metal Boot on QEMU

Bare-metal boot-up implementation for the STM32F405 (Cortex-M4F) running
on QEMU. Covers the full path from hardware reset to a running `main()`
with a working SysTick interrupt, all without any vendor libraries or RTOS.

---

## Memory Map

| Region | Start        | End          | Size  | Usage                              |
|--------|--------------|--------------|-------|------------------------------------|
| FLASH  | `0x08000000` | `0x080FFFFF` | 1 MB  | Vector table, code, constants, .data init values |
| SRAM   | `0x20000000` | `0x2001FFFF` | 128 KB| Stack (from top), .data, .bss      |

**Stack pointer** starts at `0x20020000` (top of SRAM) and grows downward.

### Linker Symbol Summary

| Symbol    | Address        | Purpose                                |
|-----------|----------------|----------------------------------------|
| `_estack` | `0x20020000`   | Initial SP, first word in vector table |
| `_sidata` | `0x080002D0`   | .data load address (source in flash)   |
| `_sdata`  | `0x20000000`   | .data start in RAM (copy destination)  |
| `_edata`  | `0x20000004`   | .data end in RAM                       |
| `_sbss`   | `0x20000004`   | .bss start in RAM                      |
| `_ebss`   | `0x2000000C`   | .bss end in RAM                        |

### Section Layout (from firmware.map)

**In Flash (0x08000000):**
- `.isr_vector` at `0x08000000`, 64 bytes (16 vector entries x 4 bytes)
- `.text` at `0x08000040`, 520 bytes (all executable code)
- `.rodata` at `0x08000248`, 136 bytes (string literals for semihosting)
- `.data` LMA at `0x080002D0`, 4 bytes (initial value of `initialized = 123`)

**In SRAM (0x20000000):**
- `.data` VMA at `0x20000000`, 4 bytes (copied from flash by startup code)
- `.bss` at `0x20000004`, 8 bytes (`uninitialized` + `tick_count`)

Total flash usage: 724 bytes. Total SRAM usage: 12 bytes (plus stack growing down from top).

---

## Build Instructions

### Prerequisites

Install the ARM bare-metal toolchain and QEMU:

```
# Ubuntu/Debian
sudo apt install qemu-system-arm gcc-arm-none-eabi gdb-multiarch make

# Verify
arm-none-eabi-gcc --version
qemu-system-arm --version
```

### Build

```
make clean
make
```

This produces:
- `firmware.elf` - ELF with debug symbols (for GDB)
- `firmware.bin` - Raw binary (for QEMU)
- `firmware.map` - Linker map file

### Run on QEMU

```
make run
```

Or manually:
```
qemu-system-arm -M olimex-stm32-h405 -nographic \
    -semihosting-config enable=on,target=native \
    -kernel firmware.bin
```

Expected output:
```
Boot OK
Data/BSS verified OK
SysTick enabled, waiting for interrupts...
SysTick count: 5
SysTick count: 10
...
```

Press `Ctrl-A` then `X` to quit QEMU.

### Debug with GDB

Terminal 1 (start QEMU paused):
```
make debug
```

Terminal 2 (connect GDB):
```
arm-none-eabi-gdb firmware.elf
(gdb) target remote :3333
```

---

## Boot Sequence (Reset to main)

1. Power-on/reset occurs, the Cortex-M4 hardware takes over
2. CPU reads the word at `0x08000000` (first vector table entry) and loads it into SP, this gives us `0x20020000` (top of SRAM)
3. CPU reads the word at `0x08000004` (second entry) and loads it into PC, this is the `Reset_Handler` address with bit 0 set for Thumb mode
4. Execution begins at `Reset_Handler` in Thumb-2 mode
5. Reset_Handler copies `.data` section from its flash location (`_sidata`) to its RAM location (`_sdata` to `_edata`), giving initialized globals their correct values
6. Reset_Handler zeroes the `.bss` section in RAM (`_sbss` to `_ebss`), ensuring uninitialized globals start at zero per the C standard
7. Reset_Handler calls `main()` via `bl main`
8. `main()` prints boot messages through semihosting to confirm it was reached and that .data/.bss initialization worked correctly
9. `main()` configures SysTick: sets reload value to 16000000-1 (1 second at 16 MHz HSI), clears counter, enables timer with interrupt
10. SysTick_Handler fires every second, incrementing `tick_count` and printing a message every 5 ticks

---

## GDB Verification Evidence

Below are the GDB commands and expected results that verify each part
of the assignment. Run these after connecting GDB to QEMU as described above.

### Part A: Vector Table and Reset Handler

```
(gdb) x/2xw 0x08000000
0x8000000:  0x20020000  0x08000201
```

This confirms:
- First word is the initial SP (`0x20020000` = top of 128K RAM)
- Second word is Reset_Handler address with Thumb bit set (bit 0 = 1)

```
(gdb) info registers sp pc
sp             0x20020000          0x20020000
pc             0x8000200           0x8000200 <Reset_Handler>
```

### Part B: Runtime Initialization

```
(gdb) break main
(gdb) continue
(gdb) print initialized
$1 = 123
(gdb) print uninitialized
$2 = 0
```

This proves .data was correctly copied from flash (initialized == 123)
and .bss was properly zeroed (uninitialized == 0).

### Part E: SysTick Interrupt

```
(gdb) break SysTick_Handler
(gdb) continue
Breakpoint hit at SysTick_Handler
(gdb) print tick_count
$3 = 0
(gdb) continue
(gdb) print tick_count
$4 = 1
```

This confirms the SysTick interrupt is firing and the handler
is incrementing the counter as expected.

---

## File Structure

```
/src
    main.c              - Application code, SysTick config and handler
    semihosting.h       - Semihosting output functions for QEMU
/startup
    startup_stm32f4.s   - Vector table, Reset_Handler, runtime init
/ld
    linker.ld           - Memory layout and section definitions
Makefile                - Build system with run/debug targets
README.md               - This file
firmware.map            - Linker map (generated by build)
```
