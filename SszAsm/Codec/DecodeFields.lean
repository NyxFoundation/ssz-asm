import SszAsm.Codec.DecodeCommon

namespace SszAsm.Codec
open Asm

private def fieldSlots (fs : List (String × Schema)) : List (Nat × Schema × Nat) :=
  (fs.zipIdx.foldl (fun (state : Nat × List (Nat × Schema × Nat)) ((_, ty), i) =>
    (state.1 + ty.fixedSize.getD 4, state.2 ++ [(i, ty, state.1)])) (0, [])).2

private def readOffset (dst : Reg) (offset : Nat) : Program :=
  addConst .a0 .s0 offset ++ [.call "ssz_read_u32", .mv dst .a0]

private def firstOffset (fn : String) (slots : List (Nat × Schema × Nat))
    (width : Nat) : Program :=
  match slots.find? (fun (_, s, _) => s.fixedSize.isNone) with
  | none => exact fn .s1 width
  | some (_, _, pos) =>
    [.li .t0 width, .branch .ltu .s1 .t0 (fn ++ "_invalid")] ++
    readOffset .s7 pos ++ exact fn .s7 width

private def decodeField (fn name : String) (slots : List (Nat × Schema × Nat))
    (slot : Nat × Schema × Nat) : Program :=
  let (i, ty, pos) := slot
  (match ty.fixedSize with
   | some n => addConst .a0 .s0 pos ++ [.li .a1 n]
   | none =>
     readOffset .s7 pos ++
     (match slots.find? (fun (j, s, _) => j > i && s.fixedSize.isNone) with
      | none => [.mv .s9 .s1]
      | some (_, _, nextPos) => readOffset .s9 nextPos) ++
     [.branch .ltu .s9 .s7 (fn ++ "_invalid"),
      .branch .ltu .s1 .s9 (fn ++ "_invalid"),
      .rr .add .a0 .s0 .s7, .rr .sub .a1 .s9 .s7]) ++
  addConst .a2 .s4 (24 * i) ++ decodeCall fn (Schema.childName name i)

def decodeFields (fn name : String) (fs : List (String × Schema)) : Program :=
  let width := fixedSection fs
  if width ≥ 2^32 then ret fn (-3) else
  let slots := fieldSlots fs
  firstOffset fn slots width ++ [.li .s5 fs.length] ++ decodeArrayAlloc fn ++
  slots.flatMap (decodeField fn name slots) ++ ret fn 0

def decodeUnion (fn name : String) (os : List (Nat × Schema)) : Program :=
  [.branch .eq .s1 .zero (fn ++ "_invalid"), .load .lbu .s6 .s0 0] ++
  (os.zipIdx.flatMap fun ((tag, _), i) =>
    [.li .t0 tag, .branch .eq .s6 .t0 (fn ++ s!"_option{i}")]) ++
  [.jump (fn ++ "_invalid")] ++
  (os.zipIdx.flatMap fun (_, i) =>
    [.label (fn ++ s!"_option{i}"), .li .a1 24] ++ decodeAlloc fn ++
    [.mv .s4 .a0, .li .s5 1] ++ decodeStore ++
    [.store .sd .s6 .s2 16, .ri .addi .a0 .s0 1,
     .ri .addi .a1 .s1 (-1), .mv .a2 .s4] ++
    decodeCall fn (Schema.childName name i) ++ ret fn 0)

end SszAsm.Codec
