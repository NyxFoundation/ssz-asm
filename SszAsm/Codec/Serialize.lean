import SszAsm.Codec.Validate

namespace SszAsm.Codec
open Asm

private def capacity (fn : String) (size : Reg) : Program :=
  [.branch .ltu .s2 size (fn ++ "_capacity")] ++
    requireData fn .s1 size "_output_ok"

private def delimiter (fn : String) : Program :=
  [.shift .srli .t0 .s4 3, .rr .add .t0 .s1 .t0,
   .ri .andi .t1 .s4 7, .li .t2 1, .rr .sll .t2 .t2 .t1,
   .branch .ne .t1 .zero (fn ++ "_merge_delimiter"),
   .store .sb .t2 .t0 0, .jump (fn ++ "_delimiter_done"),
   .label (fn ++ "_merge_delimiter"), .load .lbu .t1 .t0 0,
   .rr .bitOr .t1 .t1 .t2, .store .sb .t1 .t0 0,
   .label (fn ++ "_delimiter_done")]

private def serializeLeaf (fn : String) (schema : Schema) : Program :=
  (if isBits schema then bitBytes .s5 .s4 else [.mv .s5 .s4]) ++
  (if isBitList schema then
    [.shift .srli .s6 .s4 3, .ri .addi .s6 .s6 1]
   else [.mv .s6 .s5]) ++
  (if compositeBound schema then checkBound fn .s6 else []) ++
  capacity fn .s6 ++
  [.mv .a0 .s1, .mv .a1 .s3, .mv .a2 .s5, .call "ssz_copy"] ++
  (if isBitList schema then delimiter fn else []) ++
  [.mv .a0 .s6, .jump (fn ++ "_return")]

private def arrayFixedSize (fn : String) (width : Nat) : Program :=
  if width ≥ 2^32 then
    [.branch .ne .s4 .zero (fn ++ "_overflow"), .li .s5 0]
  else
    [.li .t0 ((2^32 - 1) / width), .branch .ltu .t0 .s4 (fn ++ "_overflow"),
     .li .t0 width, .rr .mul .s5 .s4 .t0]

private def arrayStep (fn child : String) (isVariable : Bool) : Program :=
  (if isVariable then
    [.rr .add .a0 .s1 .s6, .mv .a1 .s5, .call "ssz_write_u32",
     .rr .add .a1 .s1 .s5, .rr .sub .a2 .s2 .s5]
   else [.rr .add .a1 .s1 .s6, .rr .sub .a2 .s2 .s6]) ++
  [.mv .a0 .s3, .call (child ++ "_serialize")] ++ propagate fn ++
  (if isVariable then
    [.rr .add .s5 .s5 .a0] ++ checkBound fn .s5 ++ [.ri .addi .s6 .s6 4]
   else [.rr .add .s6 .s6 .a0]) ++
  [.ri .addi .s3 .s3 24, .ri .addi .s7 .s7 1]

private def serializeArray (fn name : String) (element : Schema) : Program :=
  let isVariable := element.fixedSize.isNone
  (match element.fixedSize with
   | some width => arrayFixedSize fn width
   | none => [.li .t0 (2^30), .branch .geu .s4 .t0 (fn ++ "_overflow"),
              .shift .slli .s5 .s4 2]) ++
  capacity fn .s5 ++ [.li .s6 0, .li .s7 0, .label (fn ++ "_loop"),
    .branch .eq .s7 .s4 (fn ++ "_done")] ++
  arrayStep fn (Schema.childName name 0) isVariable ++
  [.jump (fn ++ "_loop"), .label (fn ++ "_done"),
   .mv .a0 .s5, .jump (fn ++ "_return")]

private def fieldStep (fn name : String) (entry : (String × Schema) × Nat) : Program :=
  let ((_, ty), i) := entry
  let isVariable := ty.fixedSize.isNone
  (if isVariable then
    [.rr .add .a0 .s1 .s6, .mv .a1 .s5, .call "ssz_write_u32",
     .rr .add .a1 .s1 .s5, .rr .sub .a2 .s2 .s5]
   else [.rr .add .a1 .s1 .s6, .rr .sub .a2 .s2 .s6]) ++
  addConst .a0 .s3 (24 * i) ++ [.call (Schema.childName name i ++ "_serialize")] ++
  propagate fn ++
  (if isVariable then
    [.rr .add .s5 .s5 .a0] ++ checkBound fn .s5 ++ [.ri .addi .s6 .s6 4]
   else [.rr .add .s6 .s6 .a0])

private def serializeFields (fn name : String) (fs : List (String × Schema)) : Program :=
  checkedNat fn .s5 (fixedSection fs) ++ capacity fn .s5 ++ [.li .s6 0] ++
  fs.zipIdx.flatMap (fieldStep fn name) ++
  [.mv .a0 .s5, .jump (fn ++ "_return")]

private def serializeUnion (fn name : String) (os : List (Nat × Schema)) : Program :=
  [.li .s5 1] ++ capacity fn .s5 ++
  [.load .ld .s6 .s0 16, .store .sb .s6 .s1 0] ++
  (os.zipIdx.flatMap fun ((tag, _), i) =>
    [.li .t0 tag, .branch .eq .s6 .t0 (fn ++ s!"_option{i}")]) ++
  [.jump (fn ++ "_invalid")] ++
  (os.zipIdx.flatMap fun (_, i) =>
    [.label (fn ++ s!"_option{i}"), .mv .a0 .s3,
     .ri .addi .a1 .s1 1, .ri .addi .a2 .s2 (-1),
     .call (Schema.childName name i ++ "_serialize")] ++ propagate fn ++
    [.ri .addi .a0 .a0 1, .branch .lt .a0 .zero (fn ++ "_overflow"),
     .jump (fn ++ "_return")])

def compileSerialize (name : String) (schema : Schema) : Program :=
  let fn := name ++ "_serialize"
  let body := match schema with
    | .vector e _ | .list e _ | .progressiveList e _ => serializeArray fn name e
    | .container fs | .progressiveContainer _ fs => serializeFields fn name fs
    | .compatibleUnion os => serializeUnion fn name os
    | _ => serializeLeaf fn schema
  Asm.function fn 0 (
    [.mv .s0 .a0, .mv .s1 .a1, .mv .s2 .a2, .call (name ++ "_validate")] ++
    propagate fn ++ [.load .ld .s3 .s0 0, .load .ld .s4 .s0 8] ++ body ++ errors fn)

end SszAsm.Codec
