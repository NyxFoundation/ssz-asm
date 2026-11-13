import SszAsm.Asm

namespace SszAsm.Hash.Merkle
open Asm

private def copy32 (dst src : Reg) : Program :=
  [.mv .a0 dst, .mv .a1 src, .li .a2 32, .call "ssz_copy"]

private def tailPair : Program :=
  [.mv .a0 .sp, .mv .a1 .s5, .li .a2 32, .call "ssz_copy",
   .ri .addi .a0 .sp 32, .ri .addi .a1 .sp 64, .li .a2 32, .call "ssz_copy",
   .mv .a0 .s6, .mv .a1 .sp, .call "ssz_sha256_pair"]

private def layer : Program :=
  [.mv .s5 .s1, .mv .s6 .s1, .mv .s7 .s2,
   .shift .srli .s8 .s2 1, .ri .andi .t0 .s2 1, .rr .add .s8 .s8 .t0,
   .label "ssz_merkleize_pairs", .li .t0 2,
   .branch .ltu .s7 .t0 "ssz_merkleize_tail",
   .mv .a0 .s6, .mv .a1 .s5, .call "ssz_sha256_pair",
   .ri .addi .s5 .s5 64, .ri .addi .s6 .s6 32, .ri .addi .s7 .s7 (-2),
   .jump "ssz_merkleize_pairs", .label "ssz_merkleize_tail",
   .branch .eq .s7 .zero "ssz_merkleize_next_zero"] ++ tailPair ++
  [.label "ssz_merkleize_next_zero",
   .mv .a0 .sp, .ri .addi .a1 .sp 64, .li .a2 32, .call "ssz_copy",
   .ri .addi .a0 .sp 32, .ri .addi .a1 .sp 64, .li .a2 32, .call "ssz_copy",
   .ri .addi .a0 .sp 64, .mv .a1 .sp, .call "ssz_sha256_pair",
   .mv .s2 .s8, .ri .addi .s4 .s4 1]

/-- a0=out32, a1=mutable chunks, a2=count, a3=tree depth.
    The caller guarantees count <= 2^depth and valid 32*count storage.
    Zero padding occupies fixed stack space even when the depth exceeds 64. -/
private def bounded : Program :=
  Asm.function "ssz_merkleize" 96 (
    [.mv .s0 .a0, .mv .s1 .a1, .mv .s2 .a2, .mv .s3 .a3, .li .s4 0,
     .ri .addi .a0 .sp 64, .li .a1 32, .call "ssz_zero",
     .branch .ne .s2 .zero "ssz_merkleize_loop",
     .mv .a0 .s0, .li .a1 32, .call "ssz_zero", .mv .s1 .s0, .li .s2 1,
     .label "ssz_merkleize_loop",
     .branch .eq .s4 .s3 "ssz_merkleize_done"] ++ layer ++
    [.jump "ssz_merkleize_loop", .label "ssz_merkleize_done",
     .branch .eq .s0 .s1 "ssz_merkleize_copied"] ++ copy32 .s0 .s1 ++
    [.label "ssz_merkleize_copied", .li .a0 0, .jump "ssz_merkleize_return"])

private def progressiveAt : Program :=
  Asm.function "ssz_progressive_at" 64 (
    [.mv .s0 .a0, .mv .s1 .a1, .mv .s2 .a2, .mv .s3 .a3,
     .branch .ne .s2 .zero "ssz_progressive_at_nonempty",
     .li .a1 32, .call "ssz_zero", .li .a0 0, .jump "ssz_progressive_at_return",
     .label "ssz_progressive_at_nonempty", .mv .s4 .s2, .li .t0 64,
     .branch .geu .s3 .t0 "ssz_progressive_at_take_ready",
     .li .t0 1, .rr .sll .t0 .t0 .s3,
     .branch .geu .t0 .s2 "ssz_progressive_at_take_ready", .mv .s4 .t0,
     .label "ssz_progressive_at_take_ready",
     .mv .a0 .sp, .mv .a1 .s1, .mv .a2 .s4, .mv .a3 .s3, .call "ssz_merkleize",
     .ri .addi .a0 .sp 32, .shift .slli .t0 .s4 5, .rr .add .a1 .s1 .t0,
     .rr .sub .a2 .s2 .s4, .ri .addi .a3 .s3 2, .call "ssz_progressive_at",
     .mv .a0 .s0, .mv .a1 .sp, .call "ssz_sha256_pair",
     .li .a0 0, .jump "ssz_progressive_at_return"])

/-- a0=out32, a1=mutable chunks, a2=count; the width sequence is 1,4,16,... . -/
private def progressive : Program :=
  Asm.function "ssz_merkleize_progressive" 0 (
    [.li .a3 0, .call "ssz_progressive_at", .jump "ssz_merkleize_progressive_return"])

def program : Program := bounded ++ progressiveAt ++ progressive

end SszAsm.Hash.Merkle
