import SszAsm.Codec.Common

namespace SszAsm.Codec
open Asm

/-- Decoders keep input/scope/output/arena in s0/s1/s2/s3. -/
def decodeStore : Program :=
  [.store .sd .s4 .s2 0, .store .sd .s5 .s2 8, .store .sd .zero .s2 16]

/-- Allocate a nonempty region in a1, checking arithmetic before allocator failure. -/
def decodeAlloc (fn : String) : Program :=
  [.ri .addi .t0 .a1 7, .branch .ltu .t0 .a1 (fn ++ "_overflow"),
   .ri .andi .t0 .t0 (-8), .load .ld .t1 .s3 0,
   .rr .add .t2 .t1 .t0, .branch .ltu .t2 .t1 (fn ++ "_overflow"),
   .mv .a0 .s3, .call "ssz_alloc", .branch .eq .a0 .zero (fn ++ "_capacity")]

def decodeArrayAlloc (fn : String) : Program :=
  [.li .s4 0, .branch .eq .s5 .zero (fn ++ "_allocated"),
   .li .t0 ((2^64 - 1) / 24), .branch .ltu .t0 .s5 (fn ++ "_overflow"),
   .li .t0 24, .rr .mul .a1 .s5 .t0] ++ decodeAlloc fn ++
  [.mv .s4 .a0, .label (fn ++ "_allocated")] ++ decodeStore

def decodeCall (fn child : String) : Program :=
  [.mv .a3 .s3, .call (child ++ "_deserialize")] ++ propagate fn

end SszAsm.Codec
