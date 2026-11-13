import SszAsm.Codec
import SszAsm.Runtime

open SszAsm

private def fixtures : List (String × Schema) := [
  ("u16", .uint 16), ("bytes", .byteList 64), ("bits", .bitList 16),
  ("lbytes", .list (.byteList 8) 4), ("empty_bytes", .byteList 0),
  ("empty_list", .list (.uint 16) 0), ("huge_bytes", .byteVector (2^32)),
  ("huge_list", .list (.uint 256) (2^64)),
  ("huge_element", .list (.byteVector (2^64)) 1)]

def main : IO Unit := do
  for (_, schema) in fixtures do
    if let .error error := schema.validate then throw (IO.userError error)
  let program := Runtime.program ++ fixtures.flatMap fun (name, schema) =>
    (Schema.nodes name schema).flatMap fun (n, s) => Codec.compileNode n s
  match Asm.emit program with
  | .error error => throw (IO.userError error)
  | .ok asm => (← IO.getStdout).putStr asm
