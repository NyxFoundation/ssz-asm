import SszAsm.Declarations
import SszAsm.Codec
import SszAsm.Runtime
import SszAsm.Hash

namespace SszAsm

private def definition : Asm.Line → Option String
  | .function name | .label name => some name
  | _ => none

private def reference : Asm.Line → Option String
  | .branch _ _ _ name | .jump name | .call name | .la _ name => some name
  | _ => none

private def checkSymbols (program : Asm.Program) : Except String Unit := do
  let defined ← (program.filterMap definition).foldlM
    (fun (seen : Std.HashSet String) name =>
      if seen.contains name then .error "Generated assembly contains duplicate symbols"
      else .ok (seen.insert name)) {}
  for name in program.filterMap reference do
    if !defined.contains name then throw "Generated assembly contains an undefined symbol"

/-- Generate a self-contained RV64IM translation unit, with shared routines once. -/
def compile (schemas : List (String × Schema)) : Except String Asm.Program := do
  let nodes ← declarationNodes schemas
  let program := Runtime.program ++ Hash.runtime ++
    nodes.flatMap (fun (name, schema) =>
      Codec.compileNode name schema ++ Hash.compileNode name schema)
  checkSymbols program
  return program

/-- Render typed macro assembly, rejecting invalid schemas, symbols, and operands. -/
def emitAssembly (schemas : List (String × Schema)) : Except String String := do
  Asm.emit (← compile schemas)

end SszAsm
