# =============================================================================
# Makefile - Build system for STM32F4 bare-metal firmware
#
# Targets:
#   all     - build firmware.bin (default, runs on make)
#   run     - build and launch on QEMU with semihosting output
#   debug   - build and start QEMU paused, waiting for GDB on port 3333
#   clean   - remove all generated files (.o, .elf, .bin, .map)
#
# Usage:
#   make              # just build
#   make run          # build + run on QEMU
#   make debug        # build + start debug session (needs GDB in another terminal)
#   make clean        # clean up
#
# Author: Pranav
# Course: Embedded Systems, Assignment 1
# =============================================================================

# --- Toolchain ---
# arm-none-eabi-gcc : cross compiler targeting ARM bare metal (no OS)
# arm-none-eabi-objcopy : extracts raw binary from the ELF
# arm-none-eabi-size : prints section sizes — handy for checking flash usage
CC      = arm-none-eabi-gcc
OBJCOPY = arm-none-eabi-objcopy
SIZE    = arm-none-eabi-size

# --- Project configuration ---
# output name prefix (produces firmware.elf, firmware.bin, firmware.map)
TARGET    = firmware
# C and assembly source files
C_SRCS    = src/main.c
S_SRCS    = startup/startup_stm32f4.s
# our custom linker script
LD_SCRIPT = ld/linker.ld

# Derive object file names: src/main.c -> src/main.o, etc.
OBJS = $(C_SRCS:.c=.o) $(S_SRCS:.s=.o)

# --- Compiler flags ---
# -mcpu=cortex-m4      : generate code for the Cortex-M4 core
# -mthumb              : use Thumb-2 instruction set (only ISA on Cortex-M)
# -O0                  : no optimization — makes GDB stepping predictable
# -g                   : embed debug symbols in the ELF for GDB
# -Wall                : turn on all warnings (catch stupid mistakes)
# -ffreestanding       : tell the compiler there's no hosted C environment
# -nostdlib            : don't link libc or libgcc (we have no stdlib)
# -mfpu=fpv4-sp-d16    : STM32F4 has a single-precision hardware FPU
# -mfloat-abi=hard     : use hardware FPU instructions (not software emulation)
CFLAGS = -mcpu=cortex-m4 -mthumb -O0 -g \
         -Wall -ffreestanding -nostdlib \
         -mfpu=fpv4-sp-d16 -mfloat-abi=hard

# Assembly files get the same CPU/ABI flags
ASFLAGS = $(CFLAGS)

# --- Linker flags ---
# -T  : use our custom linker script instead of the default one
# -nostdlib : no standard libraries at link time either
# -Wl,-Map : ask ld to write a map file showing where everything ended up
LDFLAGS = -T $(LD_SCRIPT) -nostdlib -Wl,-Map=$(TARGET).map

# --- QEMU settings ---
QEMU         = qemu-system-arm
QEMU_MACHINE = olimex-stm32-h405      # the QEMU STM32F405 board model
QEMU_FLAGS   = -M $(QEMU_MACHINE) -nographic \
               -semihosting-config enable=on,target=native
# NOTE: -semihosting-config is required. Without it, the bkpt 0xAB
# instruction in semihosting.h is treated as a real breakpoint and QEMU
# will either crash or produce no output.

# =============================================================================
# Build rules
# =============================================================================

# Default target: produce the raw binary
all: $(TARGET).bin

# Compile each .c file to a .o object file
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

# Assemble each .s file to a .o object file
%.o: %.s
	$(CC) $(ASFLAGS) -c $< -o $@

# Link all objects into an ELF executable
# The $(SIZE) call prints a section size summary so you can see flash usage
$(TARGET).elf: $(OBJS)
	$(CC) $(OBJS) $(LDFLAGS) -o $@
	$(SIZE) $@

# Extract raw binary from the ELF — this is what QEMU actually loads
$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

# Run the firmware on QEMU with semihosting enabled
# Ctrl-A then X to exit QEMU
run: $(TARGET).bin
	$(QEMU) $(QEMU_FLAGS) -kernel $(TARGET).bin

# Start QEMU in debug mode: halted at reset, GDB server on port 3333
# In another terminal: arm-none-eabi-gdb firmware.elf
#                      (gdb) target remote :3333
debug: $(TARGET).bin
	$(QEMU) $(QEMU_FLAGS) -kernel $(TARGET).bin -S -gdb tcp::3333

# Remove all generated build artifacts
clean:
	rm -f $(OBJS) $(TARGET).elf $(TARGET).bin $(TARGET).map

# These are not files, they're just target names
.PHONY: all clean run debug