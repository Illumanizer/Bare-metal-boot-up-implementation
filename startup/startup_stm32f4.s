/**
 Startup file for STM32F4 (Cortex-M4)
 *
 * This file does a few basic things needed before C code can run:
 *
 * 1. Defines the interrupt vector table
 * 2. Runs Reset_Handler after reset
 * 3. Sets up memory (.data and .bss)
 * 4. Calls main()
 */

    .syntax unified         /* unified ARM/Thumb syntax, required for Cortex-M */
    .cpu cortex-m4          /* tell the assembler what CPU we're targeting */
    .fpu fpv4-sp-d16        /* STM32F4 has a single-precision FPU, tell gcc */
    .thumb                  /* all code is Thumb-2 (no ARM mode on Cortex-M) */

//  Symbols imported from linker.ld

    .extern _estack      /* top of stack (end of RAM) */
    .extern _sidata      /* start of initialized data in flash */
    .extern _sdata       /* start of .data in RAM */
    .extern _edata       /* end of .data in RAM */
    .extern _sbss        /* start of .bss section */
    .extern _ebss        /* end of .bss section */

/* global visibility so the linker can find them from other files */
    .global g_pfnVectors
    .global Reset_Handler
    .global Default_Handler

/* 
 Interrupt Vector Table
   This is placed at the beginning of flash.

   When the MCU resets it reads:
   word 0 -> initial stack pointer
   word 1 -> address of Reset_Handler
*/
    .section .isr_vector, "a", %progbits   /* "a" = allocatable, not executable */
    .type g_pfnVectors, %object

g_pfnVectors:
    .word _estack               /*   Initial SP hardware loads this on reset */
    .word Reset_Handler         /*  Reset  first code that runs */
    .word NMI_Handler           /*   Non-maskable interrupt */
    .word HardFault_Handler     /*   Hard fault  catches most errors */
    .word MemManage_Handler     /*   Memory management fault (MPU violation) */
    .word BusFault_Handler      /*   Bus fault (bad memory access) */
    .word UsageFault_Handler    /*   Usage fault (undefined instruction) */

    .word 0                     
    .word 0                     // all 4 reserved
    .word 0                     
    .word 0                    

    .word SVCall_Handler        /*  SVC instruction  */
    .word DebugMon_Handler      /*  Debug monitor */
    .word 0                     /*  Reserved */
    .word PendSV_Handler        /*  Pendable service request  */
    .word SysTick_Handler       /*  SysTick timer  we override this in main.c */

    .size g_pfnVectors, . - g_pfnVectors    /* tell the linker the size of this object */

/* 
Reset_Handler

   First code that runs after reset.

   Tasks:
   1. Copy .data from flash to RAM
   2. Clear .bss section
   3. Call main()
*/
    .section .text.Reset_Handler, "ax", %progbits   /* "ax" = alloc + execute */
    .type Reset_Handler, %function
    .thumb_func                 /* ensures bit 0 of the address is set (Thumb mode) */

Reset_Handler:

    /* copy initialized variables from flash to RAM */

    ldr r0, =_sidata            /* r0 : source in flash */
    ldr r1, =_sdata             /* r1 : destination in RAM */
    ldr r2, =_edata             /* r2 : end of destination */

copy_data_loop:
    cmp  r1, r2                 /* are we at the end? */
    bhs  copy_data_done         /* if r1 >= r2 (unsigned), we're done */
    ldr  r3, [r0], #4           /* load word from flash, r0 += 4 */
    str  r3, [r1], #4           /* store word to RAM,   r1 += 4 */
    b    copy_data_loop         /* next word */

copy_data_done:

   /* clear the .bss section (set variables to zero) */

    ldr  r1, =_sbss             /* r1 = start of .bss */
    ldr  r2, =_ebss             /* r2 = end of .bss */
    movs r3, #0                 /* r3 = 0  */

zero_bss_loop:
    cmp  r1, r2                 /* reached the end? */
    bhs  zero_bss_done          /* if r1 >= r2 (unsigned), done */
    str  r3, [r1], #4           /* write zero to RAM, r1 += 4 */
    b    zero_bss_loop          /* next word */

zero_bss_done:

    // run the main program
    bl main

    // if main ever returns just stay here
hang:
    b hang

    .size Reset_Handler, . - Reset_Handler

/* 
    Default interrupt handler

   If any interrupt happen and we did not define a handler
   for it, exec will end up here

 */
    .section .text.Default_Handler, "ax", %progbits
    .type Default_Handler, %function
    .thumb_func

Default_Handler:
    b Default_Handler           /* spin forever on any unhandled exception */

    .size Default_Handler, . - Default_Handler

/* 
   Weak aliases for handlers

   These are mapped to Default_Handler by default.
   If we define a handler with the same name somewhere
   else (like SysTick_Handler in C), that one will be used.
*/
    .weak NMI_Handler
    .thumb_set NMI_Handler,       Default_Handler

    .weak HardFault_Handler
    .thumb_set HardFault_Handler,  Default_Handler

    .weak MemManage_Handler
    .thumb_set MemManage_Handler,  Default_Handler

    .weak BusFault_Handler
    .thumb_set BusFault_Handler,   Default_Handler

    .weak UsageFault_Handler
    .thumb_set UsageFault_Handler, Default_Handler

    .weak SVCall_Handler
    .thumb_set SVCall_Handler,     Default_Handler

    .weak DebugMon_Handler
    .thumb_set DebugMon_Handler,   Default_Handler

    .weak PendSV_Handler
    .thumb_set PendSV_Handler,     Default_Handler

// SysTick handler will be defined in main.c
    .weak SysTick_Handler
    .thumb_set SysTick_Handler,    Default_Handler