# ===================================================================
# Makefile - Build system for STM32F4 bare-metal firmware
#
# Targets:
#   all       - Build firmware.bin (default)
#   clean     - Remove all build artifacts
#   debug     - Launch QEMU in GDB server mode
#   run       - Run firmware on QEMU with semihosting
#
# Usage:
#   make              (builds everything)
#   make run          (builds and runs on QEMU)
#   make debug        (builds and starts QEMU waiting for GDB)
#   make clean        (removes .o, .elf, .bin, .map files)
#
# Author: Pranav
# Course: Embedded Systems, Assignment 1
# ===================================================================

# --- Toolchain ---
CC      = arm-none-eabi-gcc
OBJCOPY = arm-none-eabi-objcopy
SIZE    = arm-none-eabi-size

# --- Project files ---
TARGET    = firmware
C_SRCS    = src/main.c
S_SRCS    = startup/startup_stm32f4.s
LD_SCRIPT = ld/linker.ld

# Object files: just swap the extensions
OBJS = $(C_SRCS:.c=.o) $(S_SRCS:.s=.o)

# --- Compiler flags ---
# -mcpu=cortex-m4   : target the M4 core
# -mthumb           : use Thumb-2 instruction set
# -O0               : no optimization (easier to debug)
# -g                : include debug symbols for GDB
# -Wall             : enable all warnings
# -ffreestanding    : no hosted C environment
# -nostdlib         : do not link standard library
# -mfpu / -mfloat   : hardware FPU settings for F4
CFLAGS = -mcpu=cortex-m4 -mthumb -O0 -g \
         -Wall -ffreestanding -nostdlib \
         -mfpu=fpv4-sp-d16 -mfloat-abi=hard

# Assembly gets the same flags (same CPU/ABI settings)
ASFLAGS = $(CFLAGS)

# Linker flags: use our custom script, generate map file
LDFLAGS = -T $(LD_SCRIPT) -nostdlib -Wl,-Map=$(TARGET).map

# --- QEMU settings ---
QEMU      = qemu-system-arm
QEMU_MACHINE = olimex-stm32-h405
QEMU_FLAGS = -M $(QEMU_MACHINE) -nographic \
             -semihosting-config enable=on,target=native

# =========================== Rules ==============================

# Default target: produce the binary
all: $(TARGET).bin

# Compile C source files to object files
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

# Assemble .s files to object files
%.o: %.s
	$(CC) $(ASFLAGS) -c $< -o $@

# Link all objects into an ELF, then print size summary
$(TARGET).elf: $(OBJS)
	$(CC) $(OBJS) $(LDFLAGS) -o $@
	$(SIZE) $@

# Extract raw binary from ELF (this is what QEMU loads)
$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

# Run firmware on QEMU with semihosting output
run: $(TARGET).bin
	$(QEMU) $(QEMU_FLAGS) -kernel $(TARGET).bin

# Start QEMU paused, waiting for GDB connection on port 3333
debug: $(TARGET).bin
	$(QEMU) $(QEMU_FLAGS) -kernel $(TARGET).bin -S -gdb tcp::3333

# Remove all generated files
clean:
	rm -f $(OBJS) $(TARGET).elf $(TARGET).bin $(TARGET).map

.PHONY: all clean run debug
