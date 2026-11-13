import SszAsm.Codec.Serialize
import SszAsm.Codec.Deserialize

namespace SszAsm.Codec

/-- Emit one node; the library enumerates Schema.nodes once to include its children. -/
def compileNode (name : String) (schema : Schema) : Asm.Program :=
  compileValidate name schema ++ compileSerialize name schema ++ compileDeserialize name schema

end SszAsm.Codec
