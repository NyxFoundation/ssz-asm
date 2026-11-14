.text
.globl _start
.type _start, @function
_start:
#if defined(__x86_64__)
  and $-16, %rsp
  call test_main
  mov %rax, %rdi
  mov $60, %eax
  syscall
#elif defined(__riscv) && __riscv_xlen == 64
  call test_main
  li a7, 93
  ecall
#else
#error Unsupported test architecture
#endif
.size _start, . - _start
.section .note.GNU-stack,"",@progbits
