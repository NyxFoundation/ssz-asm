import SszAsm.Hash.Common

namespace SszAsm.Hash
open Asm

def scalar (fn : String) (bytes : Nat) : Program :=
  [.mv .a0 .s1, .li .a1 32, .call "ssz_zero",
   .mv .a0 .s1, .mv .a1 .s7, .li .a2 bytes, .call "ssz_copy"] ++ finish fn

def packed (fn : String) (bits : Bool) (capacity : Option Nat) (withLength : Bool) : Program :=
  (if bits then ceilShift .s6 .s5 3 ++ ceilShift .s4 .s5 8
   else [.mv .s6 .s5] ++ ceilShift .s4 .s5 5) ++ allocateChunks fn ++
  [.mv .a0 .s3, .mv .a1 .s7, .mv .a2 .s6, .call "ssz_copy"] ++
  tree capacity ++ (if withLength then mixLength else []) ++ finish fn

private def packElements (fn : String) (bytes : Nat) : Program :=
  [.mv .s9 .s3, .li .s8 0, .label (fn ++ "_pack_loop"),
   .branch .eq .s8 .s5 (fn ++ "_pack_done"),
   .mv .a0 .s9, .load .ld .a1 .s7 0, .li .a2 bytes, .call "ssz_copy",
   .ri .addi .s7 .s7 24, .ri .addi .s9 .s9 bytes,
   .ri .addi .s8 .s8 1, .jump (fn ++ "_pack_loop"), .label (fn ++ "_pack_done")]

def basicArray (fn : String) (bytes : Nat) (capacity : Option Nat)
    (withLength : Bool) : Program :=
  ceilShift .s4 .s5 ((32 / bytes).log2) ++ allocateChunks fn ++ packElements fn bytes ++
  tree (capacity.map fun n => (n * bytes + 31) / 32) ++
  (if withLength then mixLength else []) ++ finish fn

end SszAsm.Hash
