/*
 * linker.ld - Custom linker script for STM32F405 (Cortex-M4F)
 *
 * Memory layout based on the STM32F405 reference manual (RM0090):
 *   - Flash starts at 0x08000000, total 1MB
 *   - SRAM starts at 0x20000000, main block is 128KB
 *     (there's also CCM at 0x10000000 but we won't use it)
 *
 * The vector table MUST be at the very beginning of flash because
 * that's where the Cortex-M4 looks on reset. First word = initial SP,
 * second word = reset handler address.
 *
 * Author: Pranav
 * Course: Embedded Systems, Assignment 1
 */

/* --- Memory regions --- */
MEMORY
{
    /* Flash: 1MB starting at the standard STM32 flash base */
    FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = 1024K

    /* SRAM: 128KB main block */
    RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 128K
}

/*
 * _estack points to the TOP of RAM (stack grows downward on ARM).
 * The Cortex-M hardware reads this as the very first word from flash
 * and loads it into SP before doing anything else.
 */
_estack = ORIGIN(RAM) + LENGTH(RAM);   /* = 0x20020000 */

/* Entry point for the debugger / linker */
ENTRY(Reset_Handler)

SECTIONS
{
    /*
     * .isr_vector: the interrupt vector table.
     * This MUST be at 0x08000000 — the Cortex-M4 fetches SP and
     * the reset vector from here on power-up / reset.
     * KEEP() prevents the linker from discarding it during gc-sections.
     */
    .isr_vector :
    {
        . = ALIGN(4);
        KEEP(*(.isr_vector))
        . = ALIGN(4);
    } > FLASH

    /*
     * .text: all the executable code goes here, placed right
     * after the vector table in flash.
     */
    .text :
    {
        . = ALIGN(4);
        *(.text)
        *(.text*)          /* catch any subsections like .text.Reset_Handler */
        . = ALIGN(4);
    } > FLASH

    /*
     * .rodata: read-only data (const globals, string literals, etc.)
     * Stays in flash since there's no reason to copy it to RAM.
     */
    .rodata :
    {
        . = ALIGN(4);
        *(.rodata)
        *(.rodata*)
        . = ALIGN(4);
    } > FLASH

    /*
     * .data: initialized global/static variables.
     *
     * This is the tricky one. The variables need to LIVE in RAM at
     * runtime (VMA = RAM), but the initial values are STORED in flash
     * (LMA = FLASH). The startup code copies them from flash to RAM
     * before main() runs.
     *
     * _sidata = load address in flash (source for copy)
     * _sdata  = start of .data in RAM (destination for copy)
     * _edata  = end of .data in RAM (tells the copy loop when to stop)
     */
    _sidata = LOADADDR(.data);

    .data :
    {
        . = ALIGN(4);
        _sdata = .;         /* mark the start of .data in RAM */
        *(.data)
        *(.data*)
        . = ALIGN(4);
        _edata = .;         /* mark the end of .data in RAM */
    } > RAM AT> FLASH

    /*
     * .bss: uninitialized globals (or zero-initialized by C standard).
     * These don't take up any space in the binary/flash — they just
     * need to be zeroed out in RAM before main() starts.
     *
     * _sbss / _ebss are used by the startup code's zeroing loop.
     */
    .bss :
    {
        . = ALIGN(4);
        _sbss = .;
        *(.bss)
        *(.bss*)
        *(COMMON)           /* catch old-style C "common" symbols too */
        . = ALIGN(4);
        _ebss = .;
    } > RAM

    /*
     * Throw away debug-related frame info and C++ exception stuff
     * that we definitely don't need in a bare-metal context.
     */
    /DISCARD/ :
    {
        *(.ARM.exidx*)
        *(.ARM.attributes*)
    }
}
