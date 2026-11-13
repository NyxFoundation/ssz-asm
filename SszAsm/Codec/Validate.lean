import SszAsm.Codec.Common

namespace SszAsm.Codec
open Asm

private def validateBits (fn : String) : Program :=
  [.ri .andi .t0 .s2 7, .branch .eq .t0 .zero (fn ++ "_padding_ok"),
   .shift .srli .t1 .s2 3, .rr .add .t1 .s1 .t1,
   .load .lbu .t1 .t1 0, .rr .srl .t1 .t1 .t0,
   .branch .ne .t1 .zero (fn ++ "_invalid"), .label (fn ++ "_padding_ok")]

private def validateArray (fn child : String) : Program :=
  [.li .t0 ((2^64 - 1) / 24), .branch .ltu .t0 .s2 (fn ++ "_overflow"),
   .mv .s3 .s1, .li .s4 0, .label (fn ++ "_loop"),
   .branch .eq .s4 .s2 (fn ++ "_done"), .mv .a0 .s3,
   .call (child ++ "_validate")] ++ propagate fn ++
  [.ri .addi .s3 .s3 24, .ri .addi .s4 .s4 1,
   .jump (fn ++ "_loop"), .label (fn ++ "_done")]

private def validateFields (fn name : String) (fs : List (String × Schema)) : Program :=
  fs.zipIdx.flatMap fun (_, i) =>
    addConst .a0 .s1 (24 * i) ++ [.call (Schema.childName name i ++ "_validate")] ++
      propagate fn

private def validateUnion (fn name : String) (os : List (Nat × Schema)) : Program :=
  [.load .ld .s3 .s0 16] ++
  (os.zipIdx.flatMap fun ((tag, _), i) =>
    [.li .t0 tag, .branch .eq .s3 .t0 (fn ++ s!"_option{i}")]) ++
  [.jump (fn ++ "_invalid")] ++
  (os.zipIdx.flatMap fun (_, i) =>
    [.label (fn ++ s!"_option{i}"), .mv .a0 .s1,
     .call (Schema.childName name i ++ "_validate"), .jump (fn ++ "_return")])

private def validateBody (fn name : String) : Schema → Program
  | .boolean | .bit =>
    [.load .lbu .t0 .s1 0, .li .t1 1, .branch .ltu .t1 .t0 (fn ++ "_invalid")]
  | .bitVector _ | .bitList _ | .progressiveBitList _ => validateBits fn
  | .vector _ _ | .list _ _ | .progressiveList _ _ =>
    validateArray fn (Schema.childName name 0)
  | .container fs | .progressiveContainer _ fs => validateFields fn name fs
  | .compatibleUnion os => validateUnion fn name os
  | _ => []

/-- Representation validation deliberately has no encoded composite-size ceiling. -/
def compileValidate (name : String) (schema : Schema) : Program :=
  let fn := name ++ "_validate"
  Asm.function fn 0 (
    [.branch .eq .a0 .zero (fn ++ "_invalid"), .mv .s0 .a0,
     .load .ld .s1 .a0 0, .load .ld .s2 .a0 8] ++
    countCheck fn .s2 schema ++ requireData fn .s1 .s2 "_data_ok" ++
    validateBody fn name schema ++ ret fn 0 ++ errors fn)

end SszAsm.Codec
