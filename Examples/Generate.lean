import SszAsm

open SszAsm

def schemas : List (String × Schema) := [
  ("Message", .container [("id", .uint 64), ("payload", .byteList 4096)])]

def main : IO Unit := do
  let assembly ← match emitAssembly schemas with
    | .ok text => pure text
    | .error error => throw (IO.userError error)
  let header ← match emitHeader schemas with
    | .ok text => pure text
    | .error error => throw (IO.userError error)
  IO.FS.createDirAll ".build"
  IO.FS.writeFile ".build/message.s" assembly
  IO.FS.writeFile ".build/message.h" header
