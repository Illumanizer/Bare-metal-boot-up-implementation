#pragma once

/* 
 * Operation code used by semihosting to print a string.
 * SYS_WRITE0 expects a null terminated string.
 */

#define SEMIHOSTING_SYS_WRITE0 0x04

// This function performs a semihosting call.

static inline int semihosting_call(int reason, void *arg)
{
    int value;
    __asm volatile (
        "mov r0, %1\n" // r0 hold the operation code
        "mov r1, %2\n" // r1 holds pointer to argument
        "bkpt 0xAB\n"  // semihosting breakpoint
        "mov %0, r0\n" // return value from r0
        : "=r"(value)
        : "r"(reason), "r"(arg)
        : "r0", "r1", "memory"
    );
    return value;
}

/*
 * Helper function to print a string
 * This just calls semihosting_call with SYS_WRITE0
 */

static inline void sh_puts(const char *s)
{
    semihosting_call(SEMIHOSTING_SYS_WRITE0, (void*)s);
}
