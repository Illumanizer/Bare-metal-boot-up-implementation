/**
 * startup_stm32f4.s - Bare-metal startup for STM32F4 (Cortex-M4F)
 *
 * This file does three things:
 *   1) Defines the interrupt vector table at the start of flash
 *   2) Implements Reset_Handler which sets up the C runtime
 *   3) Provides a default (infinite loop) handler for all exceptions
 *
 * The Cortex-M4 boot process works like this:
 *   - On reset, hardware reads address 0x08000000 -> loads into SP
 *   - Then reads address 0x08000004 -> loads into PC (must have thumb bit)
 *   - CPU starts executing from Reset_Handler in Thumb mode
 *
 * Author: Pranav
 * Course: Embedded Systems, Assignment 1
 */

    .syntax unified         /* use unified ARM/Thumb syntax */
    .cpu cortex-m4          /* target CPU */
    .fpu fpv4-sp-d16        /* hardware FPU on the F4 */
    .thumb                  /* generate Thumb-2 instructions */

/* ---------- External symbols from the linker script ---------- */
/* These are defined in linker.ld and tell us where sections are */
    .extern _estack         /* top of stack (end of RAM) */
    .extern _sidata         /* .data load address in flash */
    .extern _sdata          /* .data start in RAM */
    .extern _edata          /* .data end in RAM */
    .extern _sbss           /* .bss start in RAM */
    .extern _ebss           /* .bss end in RAM */

/* Make these visible to the linker */
    .global g_pfnVectors
    .global Reset_Handler
    .global Default_Handler

/* ============================================================
 *                   VECTOR TABLE
 * ============================================================
 * Placed in .isr_vector section which the linker script puts
 * at the very start of flash (0x08000000).
 *
 * The first 16 entries are the Cortex-M4 system exceptions.
 * Entry 0 is special: it's the initial stack pointer, not a handler.
 * Entries 1-15 are exception handlers (NMI, faults, SysTick, etc.)
 *
 * Ref: ARMv7-M Architecture Reference Manual, Table B1-4
 */
    .section .isr_vector, "a", %progbits
    .type g_pfnVectors, %object

g_pfnVectors:
    .word _estack               /* 0:  Initial stack pointer */
    .word Reset_Handler         /* 1:  Reset - entry point after power-on */
    .word NMI_Handler           /* 2:  Non-maskable interrupt */
    .word HardFault_Handler     /* 3:  Hard fault - catches everything */
    .word MemManage_Handler     /* 4:  Memory management fault */
    .word BusFault_Handler      /* 5:  Bus fault (bad memory access) */
    .word UsageFault_Handler    /* 6:  Usage fault (undefined instr, etc.) */
    .word 0                     /* 7:  Reserved */
    .word 0                     /* 8:  Reserved */
    .word 0                     /* 9:  Reserved */
    .word 0                     /* 10: Reserved */
    .word SVCall_Handler        /* 11: Supervisor call (SVC instruction) */
    .word DebugMon_Handler      /* 12: Debug monitor */
    .word 0                     /* 13: Reserved */
    .word PendSV_Handler        /* 14: Pendable service request */
    .word SysTick_Handler       /* 15: SysTick timer interrupt */

    .size g_pfnVectors, . - g_pfnVectors

/* ============================================================
 *                  RESET HANDLER
 * ============================================================
 * This is the first code that runs after reset. Its job:
 *   1) Copy .data section from flash to RAM
 *   2) Zero out .bss section in RAM
 *   3) Jump to main()
 *   4) If main ever returns, hang in an infinite loop
 *
 * We can't just call main() directly because the C runtime
 * expects initialized globals (.data) and zeroed globals (.bss)
 * to already be set up. Without this, variables like
 * "int x = 123;" would contain garbage.
 */
    .section .text.Reset_Handler, "ax", %progbits
    .type Reset_Handler, %function
    .thumb_func

Reset_Handler:
    /* --- Step 1: Copy .data from flash (LMA) to RAM (VMA) --- */
    /*
     * r0 = source address in flash (_sidata)
     * r1 = destination address in RAM (_sdata)
     * r2 = end of destination (_edata)
     * r3 = temporary register for word being copied
     *
     * We copy one word (4 bytes) at a time. The post-increment
     * addressing [r0], #4 loads and advances the pointer.
     */
    ldr r0, =_sidata            /* r0 = flash source address */
    ldr r1, =_sdata             /* r1 = RAM dest start */
    ldr r2, =_edata             /* r2 = RAM dest end */

copy_data_loop:
    cmp r1, r2                  /* have we reached the end? */
    bge copy_data_done          /* if dest >= end, we're done */
    ldr r3, [r0], #4            /* load word from flash, advance r0 */
    str r3, [r1], #4            /* store word to RAM, advance r1 */
    b copy_data_loop            /* repeat */

copy_data_done:

    /* --- Step 2: Zero out .bss section --- */
    /*
     * The C standard says uninitialized globals must be zero.
     * .bss doesn't exist in flash at all (it's NOLOAD), so we
     * just fill the RAM region with zeros.
     *
     * r1 = start of .bss in RAM
     * r2 = end of .bss in RAM
     * r3 = zero value to write
     */
    ldr r1, =_sbss              /* r1 = bss start */
    ldr r2, =_ebss              /* r2 = bss end */
    movs r3, #0                 /* r3 = 0 */

zero_bss_loop:
    cmp r1, r2                  /* reached the end? */
    bge zero_bss_done           /* if yes, skip */
    str r3, [r1], #4            /* store zero, advance pointer */
    b zero_bss_loop             /* repeat */

zero_bss_done:

    /* --- Step 3: Call main() --- */
    bl main                     /* branch-with-link to main */

    /* --- Step 4: If main returns, just hang --- */
    /*
     * In a real system you might reset or enter a low-power mode,
     * but for this assignment an infinite loop is fine.
     */
hang:
    b hang

    .size Reset_Handler, . - Reset_Handler

/* ============================================================
 *                  DEFAULT HANDLER
 * ============================================================
 * A simple infinite loop. Any exception that doesn't have its
 * own handler ends up here. This is better than random behavior.
 *
 * Declared as .weak so that other files (like main.c) can define
 * their own version of any handler and the linker will pick that
 * one instead. This is how SysTick_Handler in C overrides the
 * weak assembly version.
 */
    .section .text.Default_Handler, "ax", %progbits
    .type Default_Handler, %function
    .thumb_func

Default_Handler:
    b Default_Handler           /* spin forever */

    .size Default_Handler, . - Default_Handler

/* ============================================================
 *              WEAK ALIASES FOR EXCEPTION HANDLERS
 * ============================================================
 * Each handler is declared .weak and aliased to Default_Handler.
 * This means:
 *   - If nobody defines NMI_Handler, it resolves to the
 *     Default_Handler (infinite loop) - a safe fallback.
 *   - If you define it elsewhere (e.g. SysTick_Handler in C),
 *     the linker uses YOUR version instead of the weak one.
 *
 * This is standard practice in ARM startup files.
 */
    .weak NMI_Handler
    .thumb_set NMI_Handler, Default_Handler

    .weak HardFault_Handler
    .thumb_set HardFault_Handler, Default_Handler

    .weak MemManage_Handler
    .thumb_set MemManage_Handler, Default_Handler

    .weak BusFault_Handler
    .thumb_set BusFault_Handler, Default_Handler

    .weak UsageFault_Handler
    .thumb_set UsageFault_Handler, Default_Handler

    .weak SVCall_Handler
    .thumb_set SVCall_Handler, Default_Handler

    .weak DebugMon_Handler
    .thumb_set DebugMon_Handler, Default_Handler

    .weak PendSV_Handler
    .thumb_set PendSV_Handler, Default_Handler

    /* SysTick_Handler is also weak - main.c will override it */
    .weak SysTick_Handler
    .thumb_set SysTick_Handler, Default_Handler
