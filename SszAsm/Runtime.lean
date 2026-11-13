import SszAsm.Asm

namespace SszAsm.Runtime
open Asm

private def copy : Program :=
  [.function "ssz_copy", .mv .t0 .a0,
   .label "ssz_copy_loop", .branch .eq .a2 .zero "ssz_copy_done",
   .load .lbu .t1 .a1 0, .store .sb .t1 .t0 0,
   .ri .addi .t0 .t0 1, .ri .addi .a1 .a1 1, .ri .addi .a2 .a2 (-1),
   .jump "ssz_copy_loop", .label "ssz_copy_done", .ret, .endFunction "ssz_copy"]

private def zero : Program :=
  [.function "ssz_zero", .mv .t0 .a0,
   .label "ssz_zero_loop", .branch .eq .a1 .zero "ssz_zero_done",
   .store .sb .zero .t0 0, .ri .addi .t0 .t0 1, .ri .addi .a1 .a1 (-1),
   .jump "ssz_zero_loop", .label "ssz_zero_done", .ret, .endFunction "ssz_zero"]

private def alloc : Program :=
  [.function "ssz_alloc", .load .ld .t0 .a0 0, .load .ld .t1 .a0 8,
   .ri .andi .t2 .t0 7, .branch .ne .t2 .zero "ssz_alloc_fail",
   .branch .eq .t0 .zero "ssz_alloc_fail",
   .ri .addi .t2 .a1 7, .branch .ltu .t2 .a1 "ssz_alloc_fail",
   .ri .andi .t2 .t2 (-8), .branch .ltu .t1 .t2 "ssz_alloc_fail",
   .rr .add .t3 .t0 .t2, .branch .ltu .t3 .t0 "ssz_alloc_fail",
   .rr .sub .t1 .t1 .t2, .store .sd .t3 .a0 0, .store .sd .t1 .a0 8,
   .mv .a0 .t0, .ret,
   .label "ssz_alloc_fail", .li .a0 0, .ret, .endFunction "ssz_alloc"]

private def readU32 : Program :=
  [.function "ssz_read_u32", .load .lbu .t0 .a0 0,
   .load .lbu .t1 .a0 1, .shift .slli .t1 .t1 8, .rr .bitOr .t0 .t0 .t1,
   .load .lbu .t1 .a0 2, .shift .slli .t1 .t1 16, .rr .bitOr .t0 .t0 .t1,
   .load .lbu .t1 .a0 3, .shift .slli .t1 .t1 24, .rr .bitOr .a0 .t0 .t1,
   .ret, .endFunction "ssz_read_u32"]

private def writeU32 : Program :=
  [.function "ssz_write_u32", .store .sb .a1 .a0 0,
   .shift .srli .t0 .a1 8, .store .sb .t0 .a0 1,
   .shift .srli .t0 .a1 16, .store .sb .t0 .a0 2,
   .shift .srli .t0 .a1 24, .store .sb .t0 .a0 3,
   .ret, .endFunction "ssz_write_u32"]

/-- Shared freestanding RV64IM routines. No zero-size copy dereferences memory. -/
def program : Program := copy ++ zero ++ alloc ++ readU32 ++ writeU32

end SszAsm.Runtime
