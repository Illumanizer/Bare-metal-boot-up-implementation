# Simple Makefile for building STM32F4 baremetal firmware

#  Toolchain 
CC      = armnoneeabigcc
OBJCOPY = armnoneeabiobjcopy
SIZE    = armnoneeabisize

#  Project files 
TARGET    = firmware


# Convert source file names to object file names
C_SRCS    = src/main.c
S_SRCS    = startup/startup_stm32f4.s

# custom linker script
LD_SCRIPT = ld/linker.ld

# Convert source file names to object file names
OBJS = $(C_SRCS:.c=.o) $(S_SRCS:.s=.o)

#  Compiler flags 
# cortexm4 + thumb mode
# O0 and g are useful for debugging
CFLAGS = mcpu=cortexm4 mthumb O0 g \
         Wall ffreestanding nostdlib \
         mfpu=fpv4spd16 mfloatabi=hard

# Assembly files get the same CPU/ABI flags
ASFLAGS = $(CFLAGS)

#  Linker flags 
LDFLAGS = T $(LD_SCRIPT) nostdlib Wl,Map=$(TARGET).map

#  QEMU settings 
QEMU         = qemusystemarm
QEMU_MACHINE = olimexstm32h405      # the QEMU STM32F405 board model
QEMU_FLAGS   = M $(QEMU_MACHINE) nographic \
               semihostingconfig enable=on,target=native



#  Build targets 

# default build target
all: $(TARGET).bin

# compile C files
%.o: %.c
	$(CC) $(CFLAGS) c $< o $@

# assemble .s files
%.o: %.s
	$(CC) $(ASFLAGS) c $< o $@

# link objects to create ELF
$(TARGET).elf: $(OBJS)
	$(CC) $(OBJS) $(LDFLAGS) o $@
	$(SIZE) $@

# convert ELF to raw binary
$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) O binary $< $@

# run firmware in QEMU
run: $(TARGET).bin
	$(QEMU) $(QEMU_FLAGS) kernel $(TARGET).bin

# run QEMU waiting for GDB connection
debug: $(TARGET).bin
	$(QEMU) $(QEMU_FLAGS) kernel $(TARGET).bin S gdb tcp::3333

# remove build files
clean:
	rm f $(OBJS) $(TARGET).elf $(TARGET).bin $(TARGET).map


.PHONY: all clean run debug