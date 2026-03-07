# STM32F4 Bare-Metal Boot on QEMU

**Team Members**

| Name | Roll Number |
|-----|-------------|
| Pranav Singh Sehgal | 2025EET2476 |
| Jayesh Haridas Shewale | 2025EET2483 |

This project implements a bare-metal boot sequence for the STM32F405 (Cortex-M4F) microcontroller, emulated using QEMU. The firmware goes from reset all the way to main() with a working SysTick interrupt. No HAL, no CMSIS functions, no RTOS are used . Everything is written from scratch.

Built and tested on macOS using the ARM GNU toolchain and QEMU.

---

## Memory Map

The STM32F405 has 1MB of flash starting at 0x08000000 and 128KB of SRAM starting at 0x20000000. I used the following layout:

| Region | Start        | End          | Size   |
|--------|--------------|--------------|--------|
| FLASH  | `0x08000000` | `0x080FFFFF` | 1 MB   |
| SRAM   | `0x20000000` | `0x2001FFFF` | 128 KB |

The stack pointer is set to `0x20020000` which is the top of SRAM. ARM stacks grow downward so this gives us the full 128KB to work with (excluding whatever .data and .bss use at the bottom).

### Linker Symbols

These are the symbols defined in linker.ld that the startup assembly uses:

| Symbol    | Address        | What it does                           |
|-----------|----------------|----------------------------------------|
| `_estack` | `0x20020000`   | Initial SP, loaded by hardware on reset |
| `_sidata` | `0x080002D0`   | Where .data values are stored in flash |
| `_sdata`  | `0x20000000`   | Start of .data in RAM                  |
| `_edata`  | `0x20000004`   | End of .data in RAM                    |
| `_sbss`   | `0x20000004`   | Start of .bss in RAM                   |
| `_ebss`   | `0x2000000C`   | End of .bss in RAM                     |

### How sections are laid out (from firmware.map)

In flash:
- `.isr_vector` sits at `0x08000000`, takes 64 bytes (16 entries x 4 bytes each)
- `.text` starts right after at `0x08000040`, about 520 bytes of code
- `.rodata` at `0x08000248`, 136 bytes (mostly the string literals we print via semihosting)
- `.data` initial values at `0x080002D0`, just 4 bytes (the value 123 for our test variable)

In SRAM:
- `.data` runtime copy at `0x20000000`, 4 bytes
- `.bss` at `0x20000004`, 8 bytes (the `uninitialized` variable and `tick_count`)

So overall the firmware uses about 724 bytes of flash and 12 bytes of SRAM (not counting the stack).

---



## Installation

### On Linux / WSL (Ubuntu)
```bash
sudo apt update
sudo apt install qemu-system-arm gcc-arm-none-eabi gdb-multiarch make

```

### On macOS

```bash
brew install qemu arm-none-eabi-gcc

```

Check that everything works:

```bash
arm-none-eabi-gcc --version
qemu-system-arm --version

```

---

## Building and Running

### Building the Firmware

```bash
make clean
make

```

This gives you three files:

* `firmware.elf` — has debug symbols, used with GDB
* `firmware.bin` — raw binary that QEMU loads
* `firmware.map` — the linker map showing where everything ended up

### Running on QEMU

```bash
make run

```

*(To exit QEMU, (1) Press and hold Ctrl, then press A. (2) Press x.)*

---

## Debugging

Open two terminals. In the first one, start QEMU in debug mode (it will pause and wait for a connection):

```bash
make debug

```

In the second terminal, connect GDB:

**On Linux / WSL:**

```bash
gdb-multiarch firmware.elf

```

**On macOS:**

```bash
arm-none-eabi-gdb firmware.elf

```

Then inside GDB, connect to the QEMU instance:

```gdb
(gdb) target remote :3333

```

Now you can set breakpoints, step through code, and inspect memory.

---

## Boot Sequence

Here's what happens from reset to main(), step by step:

1. Reset happens (power on or manual reset)
2. The Cortex-M4 hardware automatically reads the first word from flash (0x08000000) and puts it in SP — for us that's 0x20020000
3. Then it reads the second word (0x08000004) and jumps to that address — that's our Reset_Handler. The address has bit 0 set because Cortex-M always runs in Thumb mode
4. We're now in Reset_Handler, running in Thumb-2 mode
5. First thing Reset_Handler does is copy the .data section from flash to RAM. The initial values live in flash (at _sidata) but the variables need to be in RAM for read/write access, so we copy them over
6. Next it zeros out the .bss section in RAM. The C standard says uninitialized globals should be 0, and since .bss doesn't have any stored values in flash, we just fill it with zeros
7. Then Reset_Handler calls main() using bl
8. Inside main(), we print some messages via semihosting to verify everything worked — "Main() Reached !!!" and ".data and .bss correctly initialised !!!!"
9. main() sets up the SysTick timer: reload value of 16000000-1 (gives us a 1 second period at the default 16 MHz HSI clock), enables the counter and its interrupt
10. From here, SysTick_Handler fires every second and increments a counter. Every 5th tick it prints the count via semihosting

---

## GDB Evidence

All the evidence below is from an actual GDB session. I've also included screenshots .

### Part A — Vector Table and Reset Handler

Checking what's at the start of flash:

```gdb
(gdb) x/2xw 0x08000000
0x8000000 <g_pfnVectors>:       0x20020000      0x08000215

```

First word (0x20020000) is the initial stack pointer — top of our 128K RAM. Second word (0x08000215) is the Reset_Handler address. The 5 at the end means the Thumb bit is set (actual address is 0x08000214), which has to be set or the processor would fault.

Checking registers right after reset:

```gdb
(gdb) info registers sp pc
sp             0x20020000          0x20020000
pc             0x8000214           0x8000214 <Reset_Handler>

```

SP got loaded from the vector table correctly and PC is at Reset_Handler. Looks good.

### Part B — Runtime Initialization

Setting a breakpoint at main and checking our test variables:

```gdb
(gdb) break main
Breakpoint 1 at 0x8000172: file src/main.c, line 141.
(gdb) continue
Continuing.

Breakpoint 1, main () at src/main.c:141
141         sh_puts("Main() Reached !!! \r\n");
(gdb) print initialized
$1 = 123
(gdb) print uninitialized
$2 = 0

```

`initialized` is 123, which means the .data copy from flash to RAM worked. `uninitialized` is 0, meaning the .bss zeroing worked too. If either of these were wrong, the startup code would be broken.

### Part C — Linker Script

The map file (`firmware.map`, included in the submission) shows everything ended up in the right place:

* Vector table is at 0x08000000 which is the start of flash — this is where the hardware looks on reset, so it has to be here.
* The `.data` section has two addresses: its LMA (load address) is 0x080002D0 in flash where the initial values are stored, and its VMA (runtime address) is 0x20000000 in RAM where the variables actually live. The startup code bridges this gap by copying from one to the other.

### Part D — Observable Output

Running `make run` gives observable output in the terminal proving execution reached `main()` and properly verified the initialized values. The SysTick messages show the interrupt is firing and printing periodically.

### Part E — SysTick Interrupt

```gdb
(gdb) break SysTick_Handler
Breakpoint 2 at 0x8000154: file src/main.c, line 128.
(gdb) continue
Continuing.

Breakpoint 2, SysTick_Handler () at src/main.c:128
128         tick_count++;   /* that's it. keep ISRs short and simple */
(gdb) print tick_count
$3 = 0
(gdb) continue
Continuing.

Breakpoint 2, SysTick_Handler () at src/main.c:128
128         tick_count++;   /* that's it. keep ISRs short and simple */
(gdb) print tick_count
$4 = 1

```

`tick_count` is 0 on the first break because GDB stops at the start of the function, before `tick_count++` runs. On the second break it's 1, confirming the first increment happened.

## Screenshots

### QEMU Semihosting Output

<p align="center">
<b>Mac</b><br>
<img src="https://github.com/user-attachments/assets/0dd32718-4aa6-4b68-b035-93fc7104250c" width="800">
</p>

<p align="center">
<b>Linux / WSL</b><br>
<img src="https://github.com/user-attachments/assets/14ed5c04-ab6c-469e-a320-4f2d8dfea88a" width="800">
</p>

---

### GDB Debugging Session

<p align="center">
<img src="https://github.com/user-attachments/assets/a27a2c56-6472-4699-ae4f-3177958d1085" width="650">
</p>

---

### Debugging Terminals

<p align="center">
<b>Terminal 1 (QEMU running with GDB server)</b><br>
<img src="https://github.com/user-attachments/assets/a66e69e0-f457-424a-a243-2f6975d1e979" width="650">
</p>

<p align="center">
<b>Terminal 2 (GDB connected to QEMU)</b><br>
<img src="https://github.com/user-attachments/assets/c8e922ac-cc98-4028-9e5b-7563494189d8" width="650">
</p>

## Files

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
