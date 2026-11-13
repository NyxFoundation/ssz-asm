import SszAsm.Hash
import SszAsm.Runtime

def main : IO Unit := do
  match SszAsm.Asm.emit (SszAsm.Runtime.program ++ SszAsm.Hash.runtime) with
  | .error e => throw (IO.userError e)
  | .ok asm => (← IO.getStdout).putStr asm
