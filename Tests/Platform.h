#ifndef SSZ_TEST_PLATFORM_H
#define SSZ_TEST_PLATFORM_H

#include <stdint.h>

#if defined(__x86_64__)
#define SYS_READ 0
#define SYS_WRITE 1
#define SYS_EXIT 60

static inline int64_t syscall3(uint64_t number, uint64_t fd, const void *data, uint64_t size) {
  uint64_t result = number;
  __asm__ volatile("syscall" : "+a"(result) : "D"(fd), "S"(data), "d"(size)
                   : "rcx", "r11", "memory", "cc");
  return (int64_t)result;
}
#elif defined(__riscv) && __riscv_xlen == 64
#define SYS_READ 63
#define SYS_WRITE 64
#define SYS_EXIT 93

static inline int64_t syscall3(uint64_t number, uint64_t fd, const void *data, uint64_t size) {
  register uint64_t a0 __asm__("a0") = fd;
  register const void *a1 __asm__("a1") = data;
  register uint64_t a2 __asm__("a2") = size;
  register uint64_t a7 __asm__("a7") = number;
  __asm__ volatile("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a7) : "memory");
  return (int64_t)a0;
}
#else
#error Unsupported test architecture
#endif

#endif
