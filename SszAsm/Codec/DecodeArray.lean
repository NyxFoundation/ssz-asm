import SszAsm.Codec.DecodeCommon

namespace SszAsm.Codec
open Asm

private def fixedCount (fn : String) (width : Nat) : Program :=
  if width ≥ 2^32 then
    [.branch .ne .s1 .zero (fn ++ "_invalid"), .li .s5 0]
  else
    [.li .t0 width, .rr .remu .t1 .s1 .t0,
     .branch .ne .t1 .zero (fn ++ "_invalid"), .rr .divu .s5 .s1 .t0]

private def variableCount (fn : String) : Program :=
  [.li .s5 0, .li .s7 0, .branch .eq .s1 .zero (fn ++ "_counted"),
   .li .t0 4, .branch .ltu .s1 .t0 (fn ++ "_invalid"),
   .mv .a0 .s0, .call "ssz_read_u32", .li .t0 4,
   .branch .ltu .a0 .t0 (fn ++ "_invalid"),
   .ri .andi .t0 .a0 3, .branch .ne .t0 .zero (fn ++ "_invalid"),
   .branch .ltu .s1 .a0 (fn ++ "_invalid"),
   .mv .s7 .a0, .shift .srli .s5 .a0 2, .label (fn ++ "_counted")]

private def fixedLoop (fn child : String) (width : Nat) : Program :=
  if width ≥ 2^32 then ret fn 0 else
  [.li .s6 0, .li .s8 0, .label (fn ++ "_loop"),
   .branch .eq .s8 .s5 (fn ++ "_done"),
   .rr .add .a0 .s0 .s6, .li .a1 width, .mv .a2 .s4] ++
  decodeCall fn child ++ addConst .s6 .s6 width ++
  [.ri .addi .s4 .s4 24, .ri .addi .s8 .s8 1, .jump (fn ++ "_loop"),
   .label (fn ++ "_done")] ++ ret fn 0

private def variableLoop (fn child : String) : Program :=
  [.li .s6 0, .li .s8 0, .label (fn ++ "_loop"),
   .branch .eq .s8 .s5 (fn ++ "_done"),
   .ri .addi .s8 .s8 1, .ri .addi .s6 .s6 4, .mv .s9 .s1,
   .branch .eq .s8 .s5 (fn ++ "_next_ready"),
   .rr .add .a0 .s0 .s6, .call "ssz_read_u32", .mv .s9 .a0,
   .label (fn ++ "_next_ready"),
   .branch .ltu .s9 .s7 (fn ++ "_invalid"),
   .branch .ltu .s1 .s9 (fn ++ "_invalid"),
   .rr .add .a0 .s0 .s7, .rr .sub .a1 .s9 .s7, .mv .a2 .s4] ++
  decodeCall fn child ++
  [.mv .s7 .s9, .ri .addi .s4 .s4 24, .jump (fn ++ "_loop"),
   .label (fn ++ "_done")] ++ ret fn 0

def decodeArray (fn name : String) (schema element : Schema) : Program :=
  (match element.fixedSize with
   | some width => fixedCount fn width
   | none => variableCount fn) ++
  countCheck fn .s5 schema ++ decodeArrayAlloc fn ++
  (match element.fixedSize with
   | some width => fixedLoop fn (Schema.childName name 0) width
   | none => variableLoop fn (Schema.childName name 0))

end SszAsm.Codec
