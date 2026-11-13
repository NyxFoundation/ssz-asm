.option norvc
.option norelax
.text
.globl _start
_start:
  call example
  li a7, 93
  ecall
.section .note.GNU-stack,"",@progbits
