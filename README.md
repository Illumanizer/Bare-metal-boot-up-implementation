# STM32F4 Bare-Metal Boot on QEMU

This project implements a bare-metal boot sequence for the STM32F405 (Cortex-M4F) microcontroller, emulated using QEMU. The firmware goes from reset all the way to main() with a working SysTick interrupt. No HAL, no CMSIS functions, no RTOS — everything is written from scratch.

Built and tested on macOS (Apple Silicon) using the ARM GNU toolchain and QEMU.

---

## Memory Map

The STM32F405 has 1MB of flash starting at 0x08000000 and 128KB of SRAM starting at 0x20000000. I used the following layout:

| Region | Start        | End          | Size   |
|--------|--------------|--------------|--------|
| FLASH  | `0x08000000` | `0x080FFFFF` | 1 MB   |
| SRAM   | `0x20000000` | `0x2001FFFF` | 128 KB |

The stack pointer is set to `0x20020000` which is the top of SRAM. ARM stacks grow downward so this gives us the full 128KB to work with (minus whatever .data and .bss use at the bottom).

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

## How to Build and Run

### Installing the tools

On Linux:
```
sudo apt install qemu-system-arm gcc-arm-none-eabi gdb-multiarch make
```

On macOS (what I used):
```
brew install qemu arm-none-eabi-gcc
```

Check that everything works:
```
arm-none-eabi-gcc --version
qemu-system-arm --version
```

### Building

```
make clean
make
```

This gives you three files:
- `firmware.elf` — has debug symbols, used with GDB
- `firmware.bin` — raw binary that QEMU loads
- `firmware.map` — the linker map showing where everything ended up

### Running on QEMU

```
make run
```

Or if you want to type it out yourself:
```
qemu-system-arm -M olimex-stm32-h405 -nographic \
    -semihosting-config enable=on,target=native \
    -kernel firmware.bin
```

To exit QEMU, press `Ctrl-A` then `X` (press them separately, not together).

### Debugging with GDB

Open two terminals. In the first one, start QEMU in debug mode:
```
make debug
```

In the second terminal, connect GDB:
```
# on linux
gdb-multiarch firmware.elf

# on mac (what I used)
arm-none-eabi-gdb firmware.elf
```

Then inside GDB:
```
(gdb) target remote :3333
```

Now you can set breakpoints, step through code, inspect memory, etc.

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
8. Inside main(), we print some messages via semihosting to verify everything worked — "Boot OK" and "Data/BSS verified OK"
9. main() sets up the SysTick timer: reload value of 16000000-1 (gives us a 1 second period at the default 16 MHz HSI clock), enables the counter and its interrupt
10. From here, SysTick_Handler fires every second and increments a counter. Every 5th tick it prints the count via semihosting

---

## GDB Evidence

All the evidence below is from an actual GDB session on my machine. I've also included screenshots (gdb_session.png and make_run.png).

### Part A — Vector Table and Reset Handler

Checking what's at the start of flash:
```
(gdb) x/2xw 0x08000000
0x8000000 <g_pfnVectors>:       0x20020000      0x08000201
```

First word (0x20020000) is the initial stack pointer — top of our 128K RAM. Second word (0x08000201) is the Reset_Handler address. The 1 at the end is the Thumb bit, which has to be set or the processor would fault.

Checking registers right after reset:
```
(gdb) info registers sp pc
sp             0x20020000          0x20020000
pc             0x8000200           0x8000200 <Reset_Handler>
```

SP got loaded from the vector table correctly and PC is at Reset_Handler. Looks good.

### Part B — Runtime Initialization

Setting a breakpoint at main and checking our test variables:
```
(gdb) break main
Breakpoint 1 at 0x80001b4: file src/main.c, line 152.
(gdb) continue
Continuing.
Breakpoint 1, main () at src/main.c:152
152         sh_puts("Boot OK\r\n");
(gdb) print initialized
$1 = 123
(gdb) print uninitialized
$2 = 0
```

`initialized` is 123, which means the .data copy from flash to RAM worked. `uninitialized` is 0, meaning the .bss zeroing worked too. If either of these were wrong, the startup code would be broken.

### Part C — Linker Script

The map file (firmware.map, included in the submission) shows everything ended up in the right place:

- Vector table is at 0x08000000 which is the start of flash — this is where the hardware looks on reset, so it has to be here
- The .data section has two addresses: its LMA (load address) is 0x080002D0 in flash where the initial values are stored, and its VMA (runtime address) is 0x20000000 in RAM where the variables actually live. The startup code bridges this gap by copying from one to the other.
- Total flash used is about 724 bytes, SRAM is 12 bytes plus the stack

### Part D — Observable Output

Running `make run` gives this output in the terminal (see make_run.png):

```
Boot OK
Data/BSS verified OK
SysTick enabled, waiting for interrupts...
SysTick count: 5
SysTick count: 10
SysTick count: 15
...
```

"Boot OK" proves we reached main(). "Data/BSS verified OK" means the if-check in main() passed — initialized was 123 and uninitialized was 0. The SysTick messages show the interrupt is firing and printing periodically.

### Part E — SysTick Interrupt

```
(gdb) break SysTick_Handler
Breakpoint 2 at 0x8000122: file src/main.c, line 110.
(gdb) continue
Continuing.
Breakpoint 2, SysTick_Handler () at src/main.c:110
110         tick_count++;
(gdb) print tick_count
$3 = 0
(gdb) continue
Continuing.
Breakpoint 2, SysTick_Handler () at src/main.c:110
110         tick_count++;
(gdb) print tick_count
$4 = 1
```

tick_count is 0 on the first break because GDB stops at the start of the function, before tick_count++ runs. On the second break it's 1, confirming the first increment happened. The periodic semihosting output (see Part D) also shows the interrupt keeps firing.

### Screenshots

GDB session:

<img width="541" height="520" alt="gdb session" src="https://github.com/user-attachments/assets/a27a2c56-6472-4699-ae4f-3177958d1085" />

QEMU semihosting output:

<img width="824" height="189" alt="make run" src="https://github.com/user-attachments/assets/0dd32718-4aa6-4b68-b035-93fc7104250c" />

---

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