import SszAsm.Codec.DecodeCommon

namespace SszAsm.Codec
open Asm

private def readBitLength (fn : String) : Program :=
  [.branch .eq .s1 .zero (fn ++ "_invalid"),
   .ri .addi .s6 .s1 (-1), .li .t0 (2^61),
   .branch .geu .s6 .t0 (fn ++ "_overflow"),
   .rr .add .t0 .s0 .s6, .load .lbu .s7 .t0 0,
   .branch .eq .s7 .zero (fn ++ "_invalid"),
   .mv .t0 .s7, .li .s8 0, .label (fn ++ "_find_delimiter"),
   .shift .srli .t0 .t0 1, .branch .eq .t0 .zero (fn ++ "_delimiter_found"),
   .ri .addi .s8 .s8 1, .jump (fn ++ "_find_delimiter"),
   .label (fn ++ "_delimiter_found"), .shift .slli .s5 .s6 3,
   .rr .add .s5 .s5 .s8] ++ bitBytes .s6 .s5

private def clearDelimiter (fn : String) : Program :=
  [.branch .eq .s8 .zero (fn ++ "_cleared"),
   .li .t0 1, .rr .sll .t0 .t0 .s8, .ri .addi .t0 .t0 (-1),
   .rr .bitAnd .t0 .s7 .t0, .rr .add .t1 .s4 .s6,
   .store .sb .t0 .t1 (-1), .label (fn ++ "_cleared")]

private def leafStorage (fn : String) : Program :=
  [.li .s4 0, .branch .eq .s6 .zero (fn ++ "_leaf_copied"), .mv .a1 .s6] ++
  decodeAlloc fn ++ [.mv .s4 .a0, .mv .a1 .s0, .mv .a2 .s6, .call "ssz_copy",
    .label (fn ++ "_leaf_copied")]

def decodeLeaf (fn name : String) (schema : Schema) : Program :=
  (if isBitList schema then readBitLength fn else
    match schema with
    | .bitVector n => exact fn .s1 ((n + 7) / 8) ++
        (if n < 2^64 then [.li .s5 n, .mv .s6 .s1] else [.jump (fn ++ "_overflow")])
    | _ => [.mv .s5 .s1, .mv .s6 .s1]) ++
  countCheck fn .s5 schema ++ leafStorage fn ++
  (if isBitList schema then clearDelimiter fn else []) ++ decodeStore ++
  [.mv .a0 .s2, .call (name ++ "_validate"), .jump (fn ++ "_return")]

end SszAsm.Codec
