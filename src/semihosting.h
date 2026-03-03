/**
 * semihosting.h - Minimal ARM semihosting for QEMU output
 *
 * Semihosting is a mechanism where the target (our firmware) can
 * make requests to the host (QEMU) through special breakpoint
 * instructions. We use it to print text to the terminal since
 * the QEMU STM32 model doesn't give us working GPIO pins.
 *
 * How it works:
 *   - We put the semihosting operation number in r0
 *   - We put the argument pointer in r1
 *   - We execute bkpt 0xAB (the ARM semihosting trap)
 *   - QEMU intercepts this, performs the operation, returns in r0
 *
 * QEMU must be launched with:
 *   -semihosting-config enable=on,target=native
 *
 * Ref: ARM DUI 0058 Semihosting for AArch32 and AArch64
 *
 * Author: Pranav
 * Course: Embedded Systems, Assignment 1
 */

#ifndef SEMIHOSTING_H
#define SEMIHOSTING_H

/*
 * SYS_WRITE0 (0x04): writes a null-terminated string to the
 * debug console. The argument is just a pointer to the string.
 * This is the simplest semihosting call for printing output.
 */
#define SEMIHOSTING_SYS_WRITE0  0x04

/**
 * semihosting_call - Execute a semihosting request
 * @reason: the semihosting operation code (e.g. SYS_WRITE0)
 * @arg:    pointer to the operation arguments
 *
 * Returns whatever the host puts back in r0 (usually 0 on success).
 *
 * The inline asm moves our parameters into r0 and r1, triggers
 * the breakpoint, then grabs the return value from r0.
 * The clobber list tells the compiler we messed with r0, r1,
 * and potentially memory.
 */
static inline int semihosting_call(int reason, void *arg)
{
    int value;
    __asm volatile (
        "mov r0, %1\n"     /* r0 = operation code */
        "mov r1, %2\n"     /* r1 = argument pointer */
        "bkpt 0xAB\n"      /* trigger semihosting trap */
        "mov %0, r0\n"     /* grab return value */
        : "=r" (value)                  /* output */
        : "r" (reason), "r" (arg)       /* inputs */
        : "r0", "r1", "memory"          /* clobbered */
    );
    return value;
}

/**
 * sh_puts - Print a string via semihosting
 * @s: null-terminated string to print
 *
 * Convenience wrapper around semihosting_call. Just pass
 * the string pointer and let SYS_WRITE0 do its thing.
 */
static inline void sh_puts(const char *s)
{
    semihosting_call(SEMIHOSTING_SYS_WRITE0, (void *)s);
}

#endif /* SEMIHOSTING_H */
