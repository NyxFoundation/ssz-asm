import SszAsm.Hash.Sha256
import SszAsm.Hash.Merkle
import SszAsm.Hash.Packed
import SszAsm.Hash.Nested

namespace SszAsm.Hash

private def array (fn name : String) (element : Schema) (capacity : Option Nat)
    (withLength : Bool) : Asm.Program :=
  match element.basicSize with
  | some bytes => basicArray fn bytes capacity withLength
  | none => nestedArray fn name capacity withLength

private def body (fn name : String) : Schema → Asm.Program
  | .boolean | .bit | .byte => scalar fn 1
  | .uint bits => scalar fn (bits / 8)
  | .byteVector n => packed fn false (some ((n + 31) / 32)) false
  | .byteList n => packed fn false (some ((n + 31) / 32)) true
  | .progressiveByteList _ => packed fn false none true
  | .bitVector n => packed fn true (some ((n + 255) / 256)) false
  | .bitList n => packed fn true (some ((n + 255) / 256)) true
  | .progressiveBitList _ => packed fn true none true
  | .vector e n => array fn name e (some n) false
  | .list e n => array fn name e (some n) true
  | .progressiveList e _ => array fn name e none true
  | .container fs => fields fn name fs.length none
  | .progressiveContainer active fs => fields fn name fs.length (some active)
  | .compatibleUnion options => union fn name options

/-- The public entry validates once; recursive roots restore each scratch checkpoint. -/
def compileNode (name : String) (schema : Schema) : Asm.Program :=
  rootFunction name (body (name ++ "_root") name schema) ++ publicFunction name

/-- SHA-256 and in-place Merkle helpers; all crypto executes as generated RV64IM. -/
def runtime : Asm.Program := Sha256.program ++ Merkle.program

end SszAsm.Hash
