import Std

/- The register/instruction representation and GNU-as rendering are adapted from
   Verified-zkEVM/evm-asm, EvmAsm/Codegen/Emit.lean (MIT, ZkSecurity 2026).
   This symbolic subset has no execution semantics or correctness proof. -/

namespace SszAsm.Asm

inductive Reg where
  | zero | ra | sp | gp | tp | t0 | t1 | t2 | s0 | s1
  | a0 | a1 | a2 | a3 | a4 | a5 | a6 | a7
  | s2 | s3 | s4 | s5 | s6 | s7 | s8 | s9 | s10 | s11
  | t3 | t4 | t5 | t6
  deriving Repr, BEq, DecidableEq

def emitReg (r : Reg) : String := s!"x{r.ctorIdx}"

inductive RR where
  | add | sub | mul | divu | remu | sltu | slt | sll | srl | sra
  | bitAnd | bitOr | bitXor | addw | subw
  deriving Repr, BEq

inductive RI where
  | addi | andi | ori | xori | sltiu | addiw
  deriving Repr, BEq

inductive Shift where
  | slli | srli | srai | slliw | srliw
  deriving Repr, BEq

inductive Load where
  | ld | lw | lwu | lhu | lbu | lb
  deriving Repr, BEq

inductive Store where
  | sd | sw | sh | sb
  deriving Repr, BEq

inductive Branch where
  | eq | ne | lt | ge | ltu | geu
  deriving Repr, BEq

inductive Line where
  | rr (op : RR) (rd rs1 rs2 : Reg)
  | ri (op : RI) (rd rs : Reg) (imm : Int)
  | shift (op : Shift) (rd rs : Reg) (amount : Nat)
  | load (op : Load) (rd base : Reg) (offset : Int)
  | store (op : Store) (src base : Reg) (offset : Int)
  | mv (rd rs : Reg)
  | li (rd : Reg) (value : Int)
  | branch (op : Branch) (rs1 rs2 : Reg) (target : String)
  | jump (target : String)
  | call (target : String)
  | la (rd : Reg) (symbol : String)
  | ret
  | label (name : String)
  | function (name : String)
  | endFunction (name : String)
  | text | rodata
  | align (power : Nat)
  | word (value : UInt32)
  | bytes (values : List UInt8)
  deriving Repr

abbrev Program := List Line

def emitRR : RR → String
  | .bitAnd => "and" | .bitOr => "or" | .bitXor => "xor"
  | .add => "add" | .sub => "sub" | .mul => "mul" | .divu => "divu"
  | .remu => "remu" | .sltu => "sltu" | .slt => "slt"
  | .sll => "sll" | .srl => "srl" | .sra => "sra"
  | .addw => "addw" | .subw => "subw"

def emitRI : RI → String
  | .addi => "addi" | .andi => "andi" | .ori => "ori"
  | .xori => "xori" | .sltiu => "sltiu" | .addiw => "addiw"

def emitShift : Shift → String
  | .slli => "slli" | .srli => "srli" | .srai => "srai"
  | .slliw => "slliw" | .srliw => "srliw"

def emitLoad : Load → String
  | .ld => "ld" | .lw => "lw" | .lwu => "lwu"
  | .lhu => "lhu" | .lbu => "lbu" | .lb => "lb"

def emitStore : Store → String
  | .sd => "sd" | .sw => "sw" | .sh => "sh" | .sb => "sb"

def emitBranch : Branch → String
  | .eq => "beq" | .ne => "bne" | .lt => "blt"
  | .ge => "bge" | .ltu => "bltu" | .geu => "bgeu"

def validSymbol (s : String) : Bool :=
  let chars := s.toList
  !chars.isEmpty && chars.all (fun c => c.toNat < 128 && (c.isAlphanum || c == '_')) &&
    !(chars.head!).isDigit

private def symbol (s : String) : Except String String :=
  if validSymbol s then .ok s else .error "Invalid assembly symbol"

private def immediate (n : Int) : Except String String :=
  if -2048 ≤ n && n ≤ 2047 then .ok (toString n)
  else .error "Instruction immediate is outside the signed 12-bit range"

private def emitMemory (op : String) (r base : Reg) (off : Int) : Except String String := do
  return s!"  {op} {emitReg r}, {← immediate off}({emitReg base})"

def emitLine : Line → Except String String
  | .rr op d a b => .ok s!"  {emitRR op} {emitReg d}, {emitReg a}, {emitReg b}"
  | .ri op d s n => do return s!"  {emitRI op} {emitReg d}, {emitReg s}, {← immediate n}"
  | .shift op d s n =>
    if n < (if op == .slliw || op == .srliw then 32 else 64) then
      .ok s!"  {emitShift op} {emitReg d}, {emitReg s}, {n}"
    else .error "Shift amount is outside the instruction range"
  | .load op d b n => emitMemory (emitLoad op) d b n
  | .store op s b n => emitMemory (emitStore op) s b n
  | .mv d s => .ok s!"  mv {emitReg d}, {emitReg s}"
  | .li d n =>
    if -(2^63 : Int) ≤ n && n < 2^64 then .ok s!"  li {emitReg d}, {n}"
    else .error "Constant does not fit in a 64-bit register"
  | .branch op a b l => do
    return s!"  {emitBranch op} {emitReg a}, {emitReg b}, {← symbol l}"
  | .jump l => do return s!"  j {← symbol l}"
  | .call l => do return s!"  call {← symbol l}"
  | .la d l => do return s!"  la {emitReg d}, {← symbol l}"
  | .ret => .ok "  ret"
  | .label l => do return s!"{← symbol l}:"
  | .function l => do
    let n ← symbol l
    return s!".text\n.balign 4\n.globl {n}\n.type {n}, @function\n{n}:"
  | .endFunction l => do let n ← symbol l; return s!".size {n}, .-{n}"
  | .text => .ok ".text"
  | .rodata => .ok ".section .rodata"
  | .align n =>
    if n ≤ 16 then .ok s!".p2align {n}" else .error "Alignment is too large"
  | .word n => .ok s!"  .word {n.toNat}"
  | .bytes [] => .ok ""
  | .bytes ns => .ok ("  .byte " ++ String.intercalate ", " (ns.map (toString ·.toNat)))

def emit (program : Program) : Except String String := do
  let lines ← program.mapM emitLine
  return ".option norvc\n.option norelax\n.attribute arch, \"rv64im\"\n" ++
    String.intercalate "\n" lines ++ "\n.section .note.GNU-stack,\"\",@progbits\n"

def saved : List Reg :=
  [.ra, .s0, .s1, .s2, .s3, .s4, .s5, .s6, .s7, .s8, .s9, .s10, .s11]

def localSize (locals : Nat) : Nat := (locals + 15) / 16 * 16

def frameSize (locals : Nat) : Nat := localSize locals + 112

def enter (locals : Nat := 0) : Program :=
  [.ri .addi .sp .sp (-(Int.ofNat (frameSize locals)))] ++
    saved.zipIdx.map (fun (r, i) => .store .sd r .sp (Int.ofNat (localSize locals + 8 * i)))

def leave (locals : Nat := 0) : Program :=
  (saved.zipIdx.map fun (r, i) => .load .ld r .sp (Int.ofNat (localSize locals + 8 * i))) ++
    [.ri .addi .sp .sp (Int.ofNat (frameSize locals)), .ret]

def function (name : String) (locals : Nat) (body : Program) : Program :=
  [.function name] ++ enter locals ++ body ++ [.label (name ++ "_return")] ++
    leave locals ++ [.endFunction name]

end SszAsm.Asm
