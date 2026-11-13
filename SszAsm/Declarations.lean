import SszAsm.Asm
import SszAsm.Schema

namespace SszAsm

private def unique (names : List String) : Except String Unit := do
  let _ ← names.foldlM (fun (seen : Std.HashSet String) name =>
    if seen.contains name then .error "Generated symbol names overlap"
    else .ok (seen.insert name)) {}
  return ()

/-- Check the public declarations and expand them to child-first named nodes. -/
def declarationNodes (schemas : List (String × Schema)) :
    Except String (List (String × Schema)) := do
  if schemas.isEmpty then throw "At least one schema is required"
  for (name, schema) in schemas do
    if !Asm.validSymbol name then throw "Invalid schema symbol"
    if name.startsWith "ssz_" then throw "The ssz_ symbol prefix is reserved"
    schema.validate
  let nodes := schemas.flatMap fun (name, schema) => Schema.nodes name schema
  unique (nodes.map Prod.fst)
  return nodes

/-- Declarations for the three C ABI entry points of each public schema. -/
def emitHeader (schemas : List (String × Schema)) : Except String String := do
  let _ ← declarationNodes schemas
  return "#include \"ssz_asm.h\"\n\n" ++ String.intercalate "\n"
    (schemas.map fun (name, _) => s!"SSZ_DECLARE({name});") ++ "\n"

end SszAsm
