import SszAsm.Declarations
import SszAsm.Codec
import SszAsm.Runtime
import SszAsm.Hash
import SszAsm.Asm.X64

namespace SszAsm

inductive Target where
  | rv64 | x86_64
  deriving BEq, Repr

def Target.parse : String → Except String Target
  | "rv64" => .ok .rv64
  | "x86_64" => .ok .x86_64
  | _ => .error "Expected target rv64 or x86_64"

def emitProgram (program : Asm.Program) (target : Target := .rv64) : Except String String :=
  match target with
  | .rv64 => Asm.emitAsm "" program
  | .x86_64 => Asm.X64.emit program

private def definition : Asm.Line → Option String
  | .code (.function name) | .code (.label name) => some name
  | _ => none

private def reference : Asm.Line → Option String
  | .code (.branch _ _ _ name) | .code (.jump name)
  | .code (.call name) | .code (.la _ name) => some name
  | _ => none

private def checkSymbols (program : Asm.Program) : Except String Unit := do
  let defined ← (program.filterMap definition).foldlM
    (fun (seen : Std.HashSet String) name =>
      if seen.contains name then .error "Generated assembly contains duplicate symbols"
      else .ok (seen.insert name)) {}
  for name in program.filterMap reference do
    if !defined.contains name then throw "Generated assembly contains an undefined symbol"

/-- Generate a self-contained SSZ macro program, with shared routines once. -/
def compile (schemas : List (String × Schema)) : Except String Asm.Program := do
  let nodes ← declarationNodes schemas
  let program := Runtime.program ++ Hash.runtime ++
    nodes.flatMap (fun (name, schema) =>
      Codec.compileNode name schema ++ Hash.compileNode name schema)
  checkSymbols program
  return program

/-- Render typed macro assembly, rejecting invalid schemas, symbols, and operands. -/
def emitAssembly (schemas : List (String × Schema)) (target : Target := .rv64) :
    Except String String := do
  emitProgram (← compile schemas) target

end SszAsm
