import SszAsm.Declarations

open SszAsm

#guard !(declarationNodes []).isOk
#guard !(declarationNodes [("", .byte)]).isOk
#guard (declarationNodes [("EmptyField", .container [("", .byte)])]).isOk
#guard !(declarationNodes [("bad\nlabel", .byte)]).isOk
#guard !(declarationNodes [("123name", .byte)]).isOk
#guard !(declarationNodes [("ssz_internal", .byte)]).isOk
#guard !(declarationNodes [("x", .byte), ("x", .uint 64)]).isOk
#guard !(declarationNodes [("x", .vector .byte 2), ("x_child0", .byte)]).isOk
#guard !(declarationNodes [("x", .uint 7)]).isOk
#guard !(Schema.uint 0).validate.isOk
#guard !(Schema.container [("a", .byte), ("a", .byte)]).validate.isOk
#guard !(Schema.compatibleUnion [(1, .byte), (1, .byte)]).validate.isOk
#guard !(Schema.progressiveContainer (List.replicate 257 true)
  ((List.range 257).map fun i => (toString i, .byte))).validate.isOk

private def a : Schema := .progressiveContainer [true] [("a", .byte)]
private def b : Schema := .progressiveContainer [false, true] [("b", .byte)]
private def c : Schema := .progressiveContainer [true] [("c", .byte)]
#guard Schema.compatible a b && Schema.compatible b c && !Schema.compatible a c
#guard !(Schema.compatibleUnion [(1, a), (2, b), (3, c)]).validate.isOk
#guard (declarationNodes [("Message", .container
  [("id", .uint 64), ("payload", .byteList 4096)])]).isOk
#guard match emitHeader [("Message", .byteList 4096)] with
  | .ok text => text == "#include \"ssz_asm.h\"\n\nSSZ_DECLARE(Message);\n"
  | .error _ => false
