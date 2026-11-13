import SszAsm.Codec.DecodeLeaf
import SszAsm.Codec.DecodeArray
import SszAsm.Codec.DecodeFields

namespace SszAsm.Codec
open Asm

def compileDeserialize (name : String) (schema : Schema) : Program :=
  let fn := name ++ "_deserialize"
  let body := match schema with
    | .vector e _ | .list e _ | .progressiveList e _ => decodeArray fn name schema e
    | .container fs | .progressiveContainer _ fs => decodeFields fn name fs
    | .compatibleUnion os => decodeUnion fn name os
    | _ => decodeLeaf fn name schema
  Asm.function fn 0 (
    [.mv .s0 .a0, .mv .s1 .a1, .mv .s2 .a2, .mv .s3 .a3] ++
    (if compositeBound schema then checkBound fn .s1 else []) ++
    requireData fn .s0 .s1 "_input_ok" ++
    [.rr .add .t0 .s0 .s1, .branch .ltu .t0 .s0 (fn ++ "_overflow")] ++
    body ++ errors fn)

end SszAsm.Codec
