# Toolchain
CC      = arm-none-eabi-gcc
OBJCOPY = arm-none-eabi-objcopy
SIZE    = arm-none-eabi-size

# Project files
TARGET    = firmware
C_SRCS    = src/main.c
S_SRCS    = startup/startup_stm32f4.s
LD_SCRIPT = ld/linker.ld

# Convert source file names to object file names
OBJS = $(C_SRCS:.c=.o) $(S_SRCS:.s=.o)

# Compiler flags

# cortex-m4 + thumb mode
# -O0 and -g are useful for debugging
CFLAGS = -mcpu=cortex-m4 -mthumb -O0 -g \
         -Wall -ffreestanding -nostdlib \
         -mfpu=fpv4-sp-d16 -mfloat-abi=hard

# Assembly files get the same CPU/ABI flags
ASFLAGS = $(CFLAGS)

# Linker flags
LDFLAGS = -T $(LD_SCRIPT) -nostdlib -Wl,-Map=$(TARGET).map

#QEMU settings
QEMU         = qemu-system-arm
QEMU_MACHINE = olimex-stm32-h405      # the QEMU STM32F405 board model
# semihosting is required for printf-style output
QEMU_FLAGS   = -M $(QEMU_MACHINE) -nographic \
               -semihosting-config enable=on,target=native



# Build targets


# Default build target: produce the raw binary
all: $(TARGET).bin

# Compile each .c file to a .o object file
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

# Assemble each .s file to a .o object file
%.o: %.s
	$(CC) $(ASFLAGS) -c $< -o $@

# Link all objects into an ELF executable
$(TARGET).elf: $(OBJS)
	$(CC) $(OBJS) $(LDFLAGS) -o $@
	$(SIZE) $@

# Extract raw binary from the ELF — this is what QEMU actually loads
$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

# Run the firmware on QEMU with semihosting enabled
run: $(TARGET).bin
	$(QEMU) $(QEMU_FLAGS) -kernel $(TARGET).bin

# run QEMU waiting for GDB connection
debug: $(TARGET).bin
	$(QEMU) $(QEMU_FLAGS) -kernel $(TARGET).bin -S -gdb tcp::3333

# remove build files
clean:
	rm -f $(OBJS) $(TARGET).elf $(TARGET).bin $(TARGET).map

.PHONY: all clean run debug