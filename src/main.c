/**
 * main.c - Bare-metal application for STM32F4 on QEMU
 *
 * This file contains:
 *   - Verification of .data and .bss initialization
 *   - SysTick timer configuration using direct register writes
 *   - SysTick interrupt handler with a tick counter
 *   - Semihosting output to prove everything works
 *
 * No HAL, no CMSIS functions - just raw register addresses.
 *
 * Author: Pranav
 * Course: Embedded Systems, Assignment 1
 */

#include "semihosting.h"
#include <stdint.h>

/* ---------------------------------------------------------------
 * SysTick register addresses (from ARMv7-M Architecture Ref Manual)
 *
 * These registers are part of the Cortex-M4 core itself, not the
 * STM32 peripheral set. They are always at the same addresses
 * on any Cortex-M processor.
 *
 * SYST_CSR  (Control and Status): enable timer, enable interrupt,
 *           select clock source, check COUNTFLAG
 * SYST_RVR  (Reload Value): counter reloads to this when it hits 0
 * SYST_CVR  (Current Value): the live down-counter value
 * --------------------------------------------------------------- */
#define SYST_CSR    (*(volatile uint32_t *)0xE000E010)
#define SYST_RVR    (*(volatile uint32_t *)0xE000E014)
#define SYST_CVR    (*(volatile uint32_t *)0xE000E018)

/* CSR bit definitions (easier to read than magic numbers) */
#define SYSTICK_ENABLE      (1U << 0)   /* bit 0: counter enable */
#define SYSTICK_TICKINT     (1U << 1)   /* bit 1: interrupt on count to 0 */
#define SYSTICK_CLKSOURCE   (1U << 2)   /* bit 2: 1 = processor clock */

/*
 * The STM32F405 on QEMU runs at 16 MHz by default (internal HSI).
 * We want SysTick to fire once per second, so reload = 16000000 - 1.
 * (The -1 is because counting is zero-inclusive: 0 to N is N+1 ticks)
 */
#define SYSTICK_RELOAD_1SEC (16000000U - 1U)

/* ---------------------------------------------------------------
 * Global variables for testing runtime initialization
 *
 * initialized goes into .data (has an initial value in flash).
 * uninitialized goes into .bss (should be zeroed by startup code).
 * --------------------------------------------------------------- */
int initialized = 123;
int uninitialized;

/*
 * Tick counter - updated by the interrupt handler.
 * MUST be volatile so the compiler does not optimize away reads
 * in the main loop. Without volatile, the compiler might cache
 * the value in a register and never see it change.
 */
volatile uint32_t tick_count = 0;

/* ---------------------------------------------------------------
 * itoa_simple - Convert an integer to a decimal string
 *
 * We cannot use sprintf or any libc function (we are nostdlib),
 * so here is a bare-bones integer-to-string converter.
 * Only handles non-negative numbers, which is fine for our
 * tick counter.
 * --------------------------------------------------------------- */
static void itoa_simple(uint32_t val, char *buf)
{
    char temp[12];          /* enough for a 32-bit number */
    int i = 0;

    /* special case: zero */
    if (val == 0) {
        buf[0] = '0';
        buf[1] = '\0';
        return;
    }

    /* pull off digits from least significant end */
    while (val > 0) {
        temp[i++] = '0' + (val % 10);
        val /= 10;
    }

    /* reverse into the output buffer */
    int j = 0;
    while (i > 0) {
        buf[j++] = temp[--i];
    }
    buf[j] = '\0';
}

/* ---------------------------------------------------------------
 * SysTick_Handler - Called by hardware every time SysTick hits 0
 *
 * This function overrides the weak alias in the startup file
 * because the linker prefers a strong symbol over a weak one.
 * The name must match EXACTLY what is in the vector table.
 *
 * Every 5 ticks (i.e. every 5 seconds), we print a message
 * via semihosting to prove the interrupt is firing periodically.
 * --------------------------------------------------------------- */
void SysTick_Handler(void)
{
    tick_count++;

    /* Print a status message every 5 seconds */
    if ((tick_count % 5) == 0) {
        char buf[20];
        sh_puts("SysTick count: ");
        itoa_simple(tick_count, buf);
        sh_puts(buf);
        sh_puts("\r\n");
    }
}

/* ---------------------------------------------------------------
 * setup_systick - Configure and enable the SysTick timer
 *
 * Steps:
 *   1. Set the reload value (how far to count down)
 *   2. Clear the current value register (resets the counter)
 *   3. Enable the timer with interrupt and processor clock
 * --------------------------------------------------------------- */
static void setup_systick(void)
{
    SYST_RVR = SYSTICK_RELOAD_1SEC;     /* count from this to zero */
    SYST_CVR = 0;                        /* writing anything clears it */

    /* Turn on: enable + interrupt + use processor clock */
    SYST_CSR = SYSTICK_ENABLE | SYSTICK_TICKINT | SYSTICK_CLKSOURCE;
}

/* ---------------------------------------------------------------
 * main - Entry point after runtime initialization
 *
 * By the time we get here, the startup code has already:
 *   - Copied .data from flash to RAM (so initialized == 123)
 *   - Zeroed .bss (so uninitialized == 0)
 *
 * We verify this, set up SysTick, and then spin in a loop
 * while the interrupt handler does its thing.
 * --------------------------------------------------------------- */
int main(void)
{
    /* announce that we made it to main */
    sh_puts("Boot OK\r\n");

    /* verify that .data and .bss init worked correctly */
    if (initialized == 123 && uninitialized == 0) {
        sh_puts("Data/BSS verified OK\r\n");
    } else {
        sh_puts("ERROR: runtime init failed!\r\n");
    }

    /* get SysTick going */
    setup_systick();
    sh_puts("SysTick enabled, waiting for interrupts...\r\n");

    /*
     * Main loop does nothing - all the action happens in the
     * SysTick interrupt handler. In a real application you would
     * do useful work here or enter a low-power sleep mode.
     */
    while (1) {
        /* spin - interrupts will fire in the background */
    }

    /* never reached, but keeps the compiler happy */
    return 0;
}
