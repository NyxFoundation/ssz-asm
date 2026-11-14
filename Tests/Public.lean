import SszAsm

open SszAsm

private def require (condition : Bool) : IO Unit :=
  unless condition do throw (IO.userError "Public assembly generation check failed")

def main : IO Unit := do
  let schemas : List (String × Schema) := [
    ("Message", .container [("id", .uint 64), ("payload", .byteList 4096)]),
    ("Flags", .bitList 256)]
  let program ← match compile schemas with
    | .ok p => pure p
    | .error e => throw (IO.userError e)
  for target in [Target.rv64, .x86_64] do
    let asm ← IO.ofExcept (emitProgram program target)
    require ((asm.splitOn ".globl Message_serialize").length == 2)
    require ((asm.splitOn ".globl Message_deserialize").length == 2)
    require ((asm.splitOn ".globl Message_hash_tree_root").length == 2)
    require ((asm.splitOn ".globl ssz_copy").length == 2)
  require (!(emitAssembly [("bad;symbol", .byte)]).isOk)
  require (!(emitAssembly [("A", .byte), ("A", .byte)]).isOk)
