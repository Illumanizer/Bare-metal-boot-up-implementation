/*
 * Linker script for STM32F405 (Cortex-M4).
 *
 * Defines memory layout and where different sections of the program
 * (.text, .data, .bss, vector table) should be placed.
 */


ENTRY(Reset_Handler) // program starts from Reset_Handler

/* 
  Memory regions on STM32F405 
   Flash  : program storage
   RAM    : runtime data and stack
*/

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = 1024K
    RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 128K
}

// Top of stack (end of RAM)
_estack = ORIGIN(RAM) + LENGTH(RAM);   /* 0x20000000 + 0x20000 = 0x20020000 */

// Flash location where initial .data values are stored 
_sidata = LOADADDR(.data);

SECTIONS
{
    /* Interrupt vector table
       Must be at the start of flash */
    .isr_vector :
    {
        . = ALIGN(4);           /* 4-byte aligned start (Cortex-M requirement) */
        KEEP(*(.isr_vector))    /* keep the table even with dead-code stripping */
        . = ALIGN(4);
    } > FLASH

    // Program code 
    .text :
    {
        . = ALIGN(4);
        *(.text)                /* main .text section */
        *(.text*)               /* .text.Reset_Handler and similar subsections */
        . = ALIGN(4);
    } > FLASH

    // Read-only constants and strings 
    .rodata :
    {
        . = ALIGN(4);
        *(.rodata)
        *(.rodata*)
        . = ALIGN(4);
    } > FLASH

    /* Initialized variables
       Stored in flash but copied to RAM at startup */
    .data :
    {
        . = ALIGN(4);
        _sdata = .;             /* start of .data in RAM — startup reads this */
        *(.data)
        *(.data*)
        . = ALIGN(4);
        _edata = .;             /* end of .data in RAM — startup stops here */
    } > RAM AT> FLASH

    /* Uninitialized variables
       Startup code will set this region to zero */
    .bss :
    {
        . = ALIGN(4);
        _sbss = .;              /* start of .bss — startup begins zeroing here */
        *(.bss)
        *(.bss*)
        *(COMMON)               /* for old-style common symbols */
        . = ALIGN(4);
        _ebss = .;              /* end of .bss — startup stops zeroing here */
    } > RAM

    // Remove sections we don't need 
    /DISCARD/ :
    {
        *(.ARM.exidx*)
        *(.ARM.attributes*)
    }
}
