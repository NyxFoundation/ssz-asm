import SszAsm

open SszAsm

def schemas : List (String × Schema) := [
  ("Message", .container [("id", .uint 64), ("payload", .byteList 4096)])]

def main (args : List String) : IO Unit := do
  unless args.length ≤ 1 do throw (IO.userError "Usage: Generate.lean [rv64|x86_64]")
  let target ← IO.ofExcept (Target.parse (args.headD "rv64"))
  let assembly ← match emitAssembly schemas target with
    | .ok text => pure text
    | .error error => throw (IO.userError error)
  let header ← match emitHeader schemas with
    | .ok text => pure text
    | .error error => throw (IO.userError error)
  IO.FS.createDirAll ".build"
  IO.FS.writeFile ".build/message.s" assembly
  IO.FS.writeFile ".build/message.h" header
