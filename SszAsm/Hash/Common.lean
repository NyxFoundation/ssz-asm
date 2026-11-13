import SszAsm.Asm
import SszAsm.Schema

namespace SszAsm.Hash
open Asm

def finish (fn : String) (code : Int := 0) : Program :=
  [.li .a0 code, .jump (fn ++ "_finish")]

def propagate (fn : String) : Program :=
  [.branch .lt .a0 .zero (fn ++ "_finish")]

def addConst (dst src : Reg) (n : Nat) : Program :=
  [.li .t6 n, .rr .add dst src .t6]

/-- Ceil of an unsigned count divided by a power of two, without count+mask overflow. -/
def ceilShift (dst src : Reg) (shift : Nat) : Program :=
  [.shift .srli dst src shift, .ri .andi .t0 src (Int.ofNat (2^shift - 1)),
   .rr .sltu .t0 .zero .t0, .rr .add dst dst .t0]

def depth (limit : Nat) : Nat :=
  if limit ≤ 1 then 0 else (limit - 1).log2 + 1

/-- s4=count; obtain a zeroed 32*count buffer in s3, using the arena in s2. -/
def allocateChunks (fn : String) : Program :=
  [.li .s3 0, .branch .eq .s4 .zero (fn ++ "_allocated"),
   .li .t0 ((2^64 - 1) / 32), .branch .ltu .t0 .s4 (fn ++ "_overflow"),
   .shift .slli .a1 .s4 5, .load .ld .t0 .s2 0,
   .rr .add .t1 .t0 .a1, .branch .ltu .t1 .t0 (fn ++ "_overflow"),
   .mv .a0 .s2, .call "ssz_alloc", .branch .eq .a0 .zero (fn ++ "_capacity"),
   .mv .s3 .a0, .shift .slli .a1 .s4 5, .call "ssz_zero",
   .label (fn ++ "_allocated")]

def tree (capacity : Option Nat) : Program :=
  [.mv .a0 .s1, .mv .a1 .s3, .mv .a2 .s4] ++
  (match capacity with
   | none => [.call "ssz_merkleize_progressive"]
   | some n => [.li .a3 (depth n), .call "ssz_merkleize"])

def mixPrefix : Program :=
  [.mv .a0 .sp, .mv .a1 .s1, .li .a2 32, .call "ssz_copy",
   .ri .addi .a0 .sp 32, .li .a1 32, .call "ssz_zero"]

def mixSuffix : Program :=
  [.mv .a0 .s1, .mv .a1 .sp, .call "ssz_sha256_pair"]

def mixLength : Program := mixPrefix ++ [.store .sd .s5 .sp 32] ++ mixSuffix

def mixActive (bits : List Bool) : Program :=
  let word := bits.zipIdx.foldl (fun n (bit, i) => n + if bit then 2^i else 0) 0
  mixPrefix ++ ((List.range 4).flatMap fun i =>
    [.li .t0 ((word / 2^(64*i)) % 2^64), .store .sd .t0 .sp (Int.ofNat (32 + 8*i))]) ++
  mixSuffix

def rootFunction (name : String) (body : Program) : Program :=
  let fn := name ++ "_root"
  Asm.function fn 64 (
    [.mv .s0 .a0, .mv .s1 .a1, .mv .s2 .a2,
     .load .ld .s10 .s2 0, .load .ld .s11 .s2 8,
     .load .ld .s7 .s0 0, .load .ld .s5 .s0 8] ++ body ++
    [.label (fn ++ "_capacity")] ++ finish fn (-2) ++
    [.label (fn ++ "_overflow")] ++ finish fn (-3) ++
    [.label (fn ++ "_finish"), .store .sd .s10 .s2 0, .store .sd .s11 .s2 8,
     .jump (fn ++ "_return")])

def publicFunction (name : String) : Program :=
  let fn := name ++ "_hash_tree_root"
  Asm.function fn 0 (
    [.mv .s0 .a0, .mv .s1 .a1, .mv .s2 .a2, .call (name ++ "_validate"),
     .branch .lt .a0 .zero (fn ++ "_return"),
     .mv .a0 .s0, .mv .a1 .s1, .mv .a2 .s2, .call (name ++ "_root"),
     .jump (fn ++ "_return")])

end SszAsm.Hash
