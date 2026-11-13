import SszAsm.Hash.Common

namespace SszAsm.Hash
open Asm

def nestedArray (fn name : String) (capacity : Option Nat) (withLength : Bool) : Program :=
  [.mv .s4 .s5] ++ allocateChunks fn ++
  [.mv .s9 .s3, .li .s8 0, .label (fn ++ "_children"),
   .branch .eq .s8 .s5 (fn ++ "_children_done"),
   .mv .a0 .s7, .mv .a1 .s9, .mv .a2 .s2,
   .call (Schema.childName name 0 ++ "_root")] ++ propagate fn ++
  [.ri .addi .s7 .s7 24, .ri .addi .s9 .s9 32, .ri .addi .s8 .s8 1,
   .jump (fn ++ "_children"), .label (fn ++ "_children_done")] ++
  tree capacity ++ (if withLength then mixLength else []) ++ finish fn

def fields (fn name : String) (count : Nat) (active : Option (List Bool)) : Program :=
  let positions : List Nat := match active with
    | none => List.range count
    | some bits => (bits.zipIdx.filter (fun entry : Bool × Nat => entry.1)).map Prod.snd
  [.li .s4 (active.map List.length |>.getD count)] ++ allocateChunks fn ++
  (positions.zipIdx.flatMap fun (position, i) =>
    addConst .a0 .s7 (i * 24) ++ addConst .a1 .s3 (position * 32) ++
    [.mv .a2 .s2, .call (Schema.childName name i ++ "_root")] ++ propagate fn) ++
  tree (if active.isSome then none else some count) ++
  (active.map mixActive |>.getD []) ++ finish fn

def union (fn name : String) (options : List (Nat × Schema)) : Program :=
  [.load .ld .s5 .s0 16] ++
  (options.zipIdx.flatMap fun ((tag, _), i) =>
    [.li .t0 tag, .branch .eq .s5 .t0 (fn ++ s!"_option{i}")]) ++ finish fn (-1) ++
  (options.zipIdx.flatMap fun (_, i) =>
    [.label (fn ++ s!"_option{i}"), .mv .a0 .s7, .mv .a1 .s1, .mv .a2 .s2,
     .call (Schema.childName name i ++ "_root")] ++ propagate fn ++
    [.jump (fn ++ "_mixin")]) ++
  [.label (fn ++ "_mixin")] ++ mixLength ++ finish fn

end SszAsm.Hash
