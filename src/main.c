/**
 *   - Verifies that .data and .bss init worked (the 123 / 0 check)
 *   - Configures SysTick to fire every 1 second at 16 MHz HSI
 *   - Increments a counter in the ISR, prints in main loop (safe design)
 *   - All output goes via semihosting since QEMU has no real GPIO
 */

#include "semihosting.h"
#include <stdint.h>


#define SYST_CSR    (*(volatile uint32_t *)0xE000E010)
#define SYST_RVR    (*(volatile uint32_t *)0xE000E014)
#define SYST_CVR    (*(volatile uint32_t *)0xE000E018)

/*
 * SysTick registers
 *
 * These addresses are fixed for all Cortex-M processors.
 * They are part of the ARM system space.
 * So this is not specific to STM32.
 *
 * SYST_CSR  -> control register
 * SYST_RVR  -> reload value
 * SYST_CVR  -> current counter value
 */

/*
 * Some useful bits in the control register
 */
#define SYSTICK_ENABLE      (1U << 0)   /* start the counter */
#define SYSTICK_TICKINT     (1U << 1)   /* generate interrupt when counter reaches 0 */
#define SYSTICK_CLKSOURCE   (1U << 2)   /* use processor clock */

/*
 * We want SysTick interrupt every 1 second.
 *
 * Default clock after reset is HSI = 16 MHz.
 * That means 16,000,000 cycles in 1 second.
 *
 * SysTick counts from RELOAD down to 0.
 * So we load (16000000 - 1).
 */
#define SYSTICK_RELOAD_1SEC     (16000000U - 1U)



int initialized   = 123;
int uninitialized;          /* goes to .bss, startup must zero this */

/*
 * Global tick counter.
 * SysTick interrupt will increase this every second.
 *
 * volatile is needed because this variable changes inside an interrupt.
 * Without volatile the compiler might optimize it incorrectly.
 */

volatile uint32_t tick_count;

/*
 * Convert a number into a string.
 *
 * Normally we would use sprintf(), but we are compiling with -nostdlib
 * so standard library functions are not available.
 *
 * This simple function only handles positive numbers which is fine
 * for our counter.
 */
static void num_to_str(uint32_t val, char *buf)
{
    char tmp[16];   /* temporary storage for digits in reverse order */
    int  i = 0;     /* index into tmp */
    int  j = 0;     /* index into buf */

    /* special case: zero would never enter the while loop below */
    if (val == 0) {
        buf[0] = '0';
        buf[1] = '\0';
        return;
    }

    /*
     * Get digits one by one from the number
     * starting from the last digit
     */
    while (val > 0) {
        tmp[i++] = '0' + (val % 10);   
        val /= 10;
    }

    /*
     * Digits are currently reversed so copy them
     * in reverse order to final buffer
     */
    while (i > 0) {
        buf[j++] = tmp[--i];
    }
    buf[j] = '\0';  /* null-terminate so sh_puts can find the end */
}

/*
 * Configure and start SysTick timer
 *
 * Steps:
 * 1. Set reload value
 * 2. Clear current counter
 * 3. Enable counter and interrupt
 */
static void setup_systick(void)
{
    SYST_RVR = SYSTICK_RELOAD_1SEC;     /* set 1-second period */
    SYST_CVR = 0;                       /* clear current value (any write works) */

    /* enable counter + interrupt + use processor clock, all in one write */
    SYST_CSR = SYSTICK_ENABLE | SYSTICK_TICKINT | SYSTICK_CLKSOURCE;
}

/*
 * This function is called automatically by hardware
 * every time SysTick counter reaches zero.
 *
 * We only increase the counter here.
 * ISR should be kept small.
 */
void SysTick_Handler(void)
{
    tick_count++;   /* that's it. keep ISRs short and simple */
}

/*
 * main function
 *
 * When we reach here Reset_Handler has already:
 * - copied .data to RAM
 * - cleared .bss
 */
int main(void)
{
    /* proof we actually got here */
    sh_puts("Main() Reached !!! \r\n");

    /* check that startup init did its job */
    if (initialized == 123 && uninitialized == 0) {
        sh_puts(".data and .bss correctly initialised !!!! \r\n");
    } else {
        sh_puts("ERROR: init failed!\r\n");
    }

    /* start the timer */
    setup_systick();
    sh_puts("SysTick running ...\r\n");

    /* last_tick tracks what we already printed, so we only print on change */
    uint32_t last_tick = 0;

    /*
     * Infinite loop
     *
     * SysTick interrupt keeps updating tick_count.
     * We check when it changes and print every 5 ticks.
     */
    while (1)
    {
        uint32_t current = tick_count;  /* snapshot to avoid race */

        /* only act when tick_count actually changed */
        if (current != last_tick)
        {
            last_tick = current;

            /* print a status message every 5 ticks */
            if (current % 5 == 0)
            {
                char buf[16];  
                sh_puts("SysTick count: ");
                num_to_str(current, buf);
                sh_puts(buf);
                sh_puts("\r\n");
            }
        }
    }

    return 0;  
}