import SszAsm.Asm

namespace SszAsm.Hash.Sha256
open Asm

private def constants : List UInt32 := [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]

private def initial : List Nat := [
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
  0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]

private def working : List Reg := [.s0, .s1, .s2, .s3, .s4, .s5, .s6, .s7]

private def rotate (dst src tmp : Reg) (amount : Nat) : Program :=
  [.shift .srliw dst src amount, .shift .slliw tmp src (32 - amount),
   .rr .bitOr dst dst tmp]

/-- Source/destination exclude t4/t5, which are temporary registers. -/
private def sigma (dst src : Reg) (a b c : Nat) (logical : Bool := false) : Program :=
  rotate dst src .t4 a ++ rotate .t5 src .t4 b ++ [.rr .bitXor dst dst .t5] ++
  (if logical then [.shift .srliw .t5 src c] else rotate .t5 src .t4 c) ++
  [.rr .bitXor dst dst .t5]

private def bigEndianWord (index : Nat) : Program :=
  let off := Int.ofNat (index * 4)
  [.load .lbu .t0 .s9 off, .shift .slli .t0 .t0 24,
   .load .lbu .t1 .s9 (off + 1), .shift .slli .t1 .t1 16,
   .rr .bitOr .t0 .t0 .t1,
   .load .lbu .t1 .s9 (off + 2), .shift .slli .t1 .t1 8,
   .rr .bitOr .t0 .t0 .t1, .load .lbu .t1 .s9 (off + 3),
   .rr .bitOr .t0 .t0 .t1, .store .sw .t0 .sp off]

private def schedule : Program :=
  (List.range 16).flatMap bigEndianWord ++
  [.ri .addi .s10 .sp 64, .ri .addi .s11 .sp 256,
   .label "ssz_sha256_compress_schedule", .load .lw .t0 .s10 (-60)] ++
  sigma .t1 .t0 7 18 3 true ++ [.load .lw .t0 .s10 (-8)] ++
  sigma .t2 .t0 17 19 10 true ++
  [.rr .addw .t1 .t1 .t2, .load .lw .t0 .s10 (-64), .rr .addw .t1 .t1 .t0,
   .load .lw .t0 .s10 (-28), .rr .addw .t1 .t1 .t0, .store .sw .t1 .s10 0,
   .ri .addi .s10 .s10 4, .branch .ne .s10 .s11 "ssz_sha256_compress_schedule"]

private def round : Program :=
  sigma .t0 .s4 6 11 25 ++
  [.rr .bitXor .t1 .s5 .s6, .rr .bitAnd .t1 .t1 .s4, .rr .bitXor .t1 .t1 .s6,
   .rr .addw .t2 .s7 .t0, .rr .addw .t2 .t2 .t1,
   .load .lw .t0 .s10 0, .rr .addw .t2 .t2 .t0,
   .load .lw .t0 .s11 0, .rr .addw .t2 .t2 .t0] ++
  sigma .t3 .s0 2 13 22 ++
  [.rr .bitAnd .t0 .s0 .s1, .rr .bitOr .t1 .s0 .s1,
   .rr .bitAnd .t1 .t1 .s2, .rr .bitOr .t0 .t0 .t1, .rr .addw .t3 .t3 .t0,
   .mv .s7 .s6, .mv .s6 .s5, .mv .s5 .s4, .rr .addw .s4 .s3 .t2,
   .mv .s3 .s2, .mv .s2 .s1, .mv .s1 .s0, .rr .addw .s0 .t2 .t3]

/-- Internal compression: a0 = eight native little-endian state words, a1 = block64. -/
private def compress : Program :=
  Asm.function "ssz_sha256_compress" 256 (
    [.mv .s8 .a0, .mv .s9 .a1] ++ schedule ++
    (working.zipIdx.map fun (r, i) => .load .lw r .s8 (Int.ofNat (4 * i))) ++
    [.mv .s10 .sp, .ri .addi .s9 .sp 256, .la .s11 "ssz_sha256_constants",
     .label "ssz_sha256_compress_round"] ++ round ++
    [.ri .addi .s10 .s10 4, .ri .addi .s11 .s11 4,
     .branch .ne .s10 .s9 "ssz_sha256_compress_round"] ++
    (working.zipIdx.flatMap fun (r, i) =>
      [.load .lw .t0 .s8 (Int.ofNat (4 * i)), .rr .addw .t0 .t0 r,
       .store .sw .t0 .s8 (Int.ofNat (4 * i))]) ++
    [.li .a0 0, .jump "ssz_sha256_compress_return"])

private def outputWord (index : Nat) : Program :=
  let off := Int.ofNat (index * 4)
  [.load .lwu .t0 .sp off, .shift .srli .t1 .t0 24, .store .sb .t1 .s0 off,
   .shift .srli .t1 .t0 16, .store .sb .t1 .s0 (off + 1),
   .shift .srli .t1 .t0 8, .store .sb .t1 .s0 (off + 2),
   .store .sb .t0 .s0 (off + 3)]

/-- SHA-256 of exactly 64 bytes: a0 = out32, a1 = input64; overlap is supported. -/
private def pair : Program :=
  Asm.function "ssz_sha256_pair" 96 (
    [.mv .s0 .a0, .mv .s1 .a1] ++
    (initial.zipIdx.flatMap fun (value, i) =>
      [.li .t0 value, .store .sw .t0 .sp (Int.ofNat (4 * i))]) ++
    [.mv .a0 .sp, .mv .a1 .s1, .call "ssz_sha256_compress",
     .ri .addi .a0 .sp 32, .li .a1 64, .call "ssz_zero",
     .li .t0 128, .store .sb .t0 .sp 32,
     .li .t0 2, .store .sb .t0 .sp 94,
     .mv .a0 .sp, .ri .addi .a1 .sp 32, .call "ssz_sha256_compress"] ++
    (List.range 8).flatMap outputWord ++
    [.li .a0 0, .jump "ssz_sha256_pair_return"])

def program : Program :=
  compress ++ pair ++ [.rodata, .align 2, .label "ssz_sha256_constants"] ++
  constants.map Line.word

end SszAsm.Hash.Sha256
