import SszAsm

def main (args : List String) : IO Unit := do
  let target ← IO.ofExcept (SszAsm.Target.parse (args.headD "rv64"))
  match SszAsm.emitProgram (SszAsm.Runtime.program ++ SszAsm.Hash.runtime) target with
  | .error e => throw (IO.userError e)
  | .ok asm => (← IO.getStdout).putStr asm
