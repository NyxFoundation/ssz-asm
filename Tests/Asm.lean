import SszAsm.Asm
import SszAsm.Schema

open SszAsm SszAsm.Asm

#guard emitReg .a0 == "x10"
#guard emitReg .s11 == "x27"
#guard emitReg .t6 == "x31"
private def emitted (line : Line) (expected : String) : Bool :=
  match emitLine line with | .ok s => s == expected | .error _ => false

private def rejected (line : Line) : Bool :=
  match emitLine line with | .error _ => true | .ok _ => false

#guard emitted (.load .lbu .a0 .a1 3) "  lbu x10, 3(x11)"
#guard emitted (.store .sd .a0 .sp 8) "  sd x10, 8(x2)"
#guard rejected (.ri .addi .sp .sp 2048)
#guard rejected (.shift .srli .a0 .a0 64)
#guard rejected (.label "unsafe\nret")
#guard Schema.fixedSize (.vector (.uint 64) 3) == some 24
#guard Schema.fixedSize (.container [("x", .uint 16), ("y", .byteList 32)]) == none
#guard frameSize 1 == 128
