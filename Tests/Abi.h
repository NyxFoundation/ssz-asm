#ifndef SSZ_TEST_ABI_H
#define SSZ_TEST_ABI_H

#include <stdint.h>

#if defined(__x86_64__)
#define ABI_SEED() \
  register uint64_t r0 __asm__("rbx") = 101, r1 __asm__("rbp") = 102; \
  register uint64_t r2 __asm__("r12") = 103, r3 __asm__("r13") = 104; \
  register uint64_t r4 __asm__("r14") = 105, r5 __asm__("r15") = 106
#define ABI_BARRIER() __asm__ volatile("" : \
  "+r"(r0), "+r"(r1), "+r"(r2), "+r"(r3), "+r"(r4), "+r"(r5) : : "memory")
#define ABI_INTACT (r0 == 101 && r1 == 102 && r2 == 103 && r3 == 104 && r4 == 105 && r5 == 106)
#elif defined(__riscv) && __riscv_xlen == 64
#define ABI_SEED() \
  register uint64_t r0 __asm__("s0") = 101, r1 __asm__("s1") = 102; \
  register uint64_t r2 __asm__("s2") = 103, r3 __asm__("s3") = 104; \
  register uint64_t r4 __asm__("s4") = 105, r5 __asm__("s5") = 106; \
  register uint64_t r6 __asm__("s6") = 107, r7 __asm__("s7") = 108; \
  register uint64_t r8 __asm__("s8") = 109, r9 __asm__("s9") = 110; \
  register uint64_t r10 __asm__("s10") = 111, r11 __asm__("s11") = 112
#define ABI_BARRIER() __asm__ volatile("" : \
  "+r"(r0), "+r"(r1), "+r"(r2), "+r"(r3), "+r"(r4), "+r"(r5), \
  "+r"(r6), "+r"(r7), "+r"(r8), "+r"(r9), "+r"(r10), "+r"(r11) : : "memory")
#define ABI_INTACT (r0 == 101 && r1 == 102 && r2 == 103 && r3 == 104 && \
  r4 == 105 && r5 == 106 && r6 == 107 && r7 == 108 && r8 == 109 && r9 == 110 && \
  r10 == 111 && r11 == 112)
#else
#error Unsupported test architecture
#endif

#endif
