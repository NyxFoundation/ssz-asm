import SszAsm

open SszAsm SszAsm.Asm

#guard (emitAssembly [("Byte", .byte)] .x86_64).isOk
#guard !(emitAssembly [("Bad", .uint 7)] .x86_64).isOk
#guard !(emitAssembly [("bad\nret", .byte)] .x86_64).isOk
#guard !(emitAssembly [("ssz_reserved", .byte)] .x86_64).isOk
#guard !(emitAssembly [("A", .byte), ("A", .byte)] .x86_64).isOk
#guard !(emitAssembly [("A", .vector .byte 2), ("A_child0", .byte)] .x86_64).isOk
#guard !(Target.parse "x86").isOk

private def rejected (body : Program) : Bool :=
  !(Asm.X64.emit (Asm.function "invalid" 0 body)).isOk

#guard rejected [.rr .div .a0 .a0 .a1]
#guard rejected [.rr .rem .a0 .a0 .a1]
#guard rejected [.mv .a0 .ra]
#guard rejected [.mv .a0 .gp]
#guard rejected [.mv .a0 .tp]
#guard rejected [.mv .a0 .a6]
#guard rejected [.mv .a7 .a0]
#guard rejected [.mv .sp .a0]
#guard rejected [.li .a0 (2^64)]
#guard rejected [.ri .addi .a0 .a0 2048]
#guard rejected [.shift .slliw .a0 .a0 32]
#guard rejected [.shift .srli .a0 .a0 64]
#guard rejected [.load .ld .a0 .a1 (-2049)]
#guard rejected [.label "bad;label"]
#guard rejected [.ret]
#guard !(Asm.X64.emit [.li .a0 1]).isOk
#guard !(Asm.X64.emit [.function "open"]).isOk
#guard !(Asm.X64.emit [.function "a", .endFunction "b"]).isOk
#guard !(Asm.X64.emit [.function "a", .function "b"]).isOk
#guard !(Asm.X64.emit [.function "a", .frameEnter 8, .frameLeave 16]).isOk
#guard !(Asm.X64.emit (Asm.function "huge" (2^31) [])).isOk

private def binary : List (String × RR) := [
  ("add", .add), ("sub", .sub), ("mul", .mul), ("divu", .divu), ("remu", .remu),
  ("sltu", .sltu), ("slt", .slt), ("sll", .sll), ("srl", .srl), ("sra", .sra),
  ("and", .bitAnd), ("or", .bitOr), ("xor", .bitXor), ("addw", .addw), ("subw", .subw)]

private def immediate : List (String × RI) := [
  ("addi", .addi), ("andi", .andi), ("ori", .ori), ("xori", .xori),
  ("slti", .slti), ("sltiu", .sltiu), ("addiw", .addiw)]

private def shifts : List (String × Shift × Nat) := [
  ("slli", .slli, 63), ("srli", .srli, 63), ("srai", .srai, 63),
  ("slliw", .slliw, 31), ("srliw", .srliw, 1)]

private def loads : List (String × Load) := [
  ("ld", .ld), ("lw", .lw), ("lwu", .lwu), ("lh", .lh),
  ("lhu", .lhu), ("lb", .lb), ("lbu", .lbu)]

private def stores : List (String × Store) := [
  ("sd", .sd), ("sw", .sw), ("sh", .sh), ("sb", .sb)]

private def branches : List (String × Branch) := [
  ("eq", .eq), ("ne", .ne), ("lt", .lt), ("ge", .ge), ("ltu", .ltu), ("geu", .geu)]

private def scalarTests : Program :=
  (binary.flatMap fun (name, op) =>
    Asm.function ("op_" ++ name) 0 [.rr op .a1 .a0 .a1, .mv .a0 .a1]) ++
  (immediate.flatMap fun (name, op) =>
    Asm.function ("op_" ++ name) 0 [.ri op .a0 .a0 (-1)]) ++
  (shifts.flatMap fun (name, op, amount) =>
    Asm.function ("op_" ++ name) 0 [.shift op .a0 .a0 amount]) ++
  (loads.flatMap fun (name, op) =>
    Asm.function ("op_" ++ name) 0 [.load op .a0 .a0 1]) ++
  (stores.flatMap fun (name, op) =>
    Asm.function ("op_" ++ name) 0 [.store op .a1 .a0 1]) ++
  (branches.flatMap fun (name, op) =>
    Asm.function ("branch_" ++ name) 0 [
      .branch op .a0 .a1 ("taken_" ++ name), .li .a0 0, .jump ("branch_" ++ name ++ "_return"),
      .label ("taken_" ++ name), .li .a0 1])

private def frameTests : Program :=
  [.function "alignment", .ri .andi .a0 .sp 15, .ret, .endFunction "alignment"] ++
  Asm.function "nested" 17 [
    .store .sd .a0 .sp 0, .mv .s11 .a1, .call "alignment",
    .branch .ne .a0 .zero "nested_return", .load .ld .a0 .sp 0,
    .rr .add .a0 .a0 .s11] ++
  Asm.function "six_args" 0 [
    .rr .add .a0 .a0 .a1, .rr .add .a0 .a0 .a2, .rr .add .a0 .a0 .a3,
    .rr .add .a0 .a0 .a4, .rr .add .a0 .a0 .a5] ++
  Asm.function "call_six" 0 [.call "six_args"] ++
  Asm.function "constants" 0 [
    .li .zero 99, .la .a0 "test_data", .load .lwu .a0 .a0 0,
    .rr .add .a0 .a0 .zero] ++
  [.rodata, .align 3, .label "test_data", .word 0xfedcba98, .bytes [0x12, 0x34]]

def main (args : List String) : IO Unit := do
  let target ← IO.ofExcept (Target.parse (args.headD "x86_64"))
  let assembly ← IO.ofExcept (emitProgram (scalarTests ++ frameTests) target)
  (← IO.getStdout).putStr assembly
