import SszAsm.Asm
import LeanAsm.ABI.SysVAMD64

namespace SszAsm.Asm.X64

open LeanAsm.X64

private abbrev Code := LeanAsm.X64.Program
private abbrev Output := LeanAsm.X64.Symbolic.Program
private abbrev XReg := LeanAsm.X64.Reg
private abbrev VReg := SszAsm.Asm.Reg

-- Virtual registers belong to each invocation, not to a shared machine state.
-- RBP addresses their slots; RSP addresses the routine's separate local storage.
private def registerBytes : Nat := 256

private def slot (reg : VReg) : Address := .base .rbp (BitVec.ofNat 32 (8 * LeanAsm.Rv64.Reg.toNat reg))

private def checkReg (reg : VReg) : Except String Unit :=
  if ([.ra, .gp, .tp, .a6, .a7] : List VReg).contains reg then
    .error "x86-64 SSZ code cannot use ra, gp, tp, a6, or a7"
  else .ok ()

private def get (dst : XReg) (src : VReg) : Except String Code := do
  checkReg src
  if src == .zero then return [.movImm .b64 dst 0]
  if src == .sp then return [.mov .b64 dst (.reg .rsp)]
  return [.mov .b64 dst (.mem (slot src))]

private def put (dst : VReg) (src : XReg) : Except String Code := do
  checkReg dst
  if dst == .zero then return []
  if dst == .sp then throw "x86-64 stack changes must use frame directives"
  return [.store .b64 (slot dst) src]

private def instructions (code : Code) : Output := code.map .instr

private def arguments : List (VReg × XReg) :=
  ([.a0, .a1, .a2, .a3, .a4, .a5] : List VReg).zip LeanAsm.ABI.SysVAMD64.argumentRegisters

private def entry : Except String Output := do
  let saves ← (LeanAsm.ABI.SysVAMD64.enter registerBytes).mapError (fun e => s!"x64: {repr e}")
  return instructions (saves ++ [.mov .b64 .rbp (.reg .rsp)] ++
    arguments.map (fun (v, r) => .store .b64 (slot v) r))

private def exit : Except String Output := do
  let restores ← (LeanAsm.ABI.SysVAMD64.leave registerBytes).mapError (fun e => s!"x64: {repr e}")
  return instructions ((← get .rax .a0) ++ restores)

private def call (name : String) : Except String Output := do
  let args ← arguments.mapM fun (v, r) => get r v
  return instructions args.flatten ++ [.call name] ++ instructions (← put .a0 .rax)

private def signWord : Code := [.extend true .b32 .b64 .rax (.reg .rax)]

private def compare (condition : Cond) : Code :=
  [.alu .cmp .b64 .rax (.reg .r10), .movImm .b64 .rax 0, .setcc condition .rax]

private def divide (remainder : Bool) : Code :=
  -- RV-style unsigned division has a defined result for a zero divisor.
  [.movImm .b64 .rcx 1, .aluImm .cmp .b64 .r10 0,
   .cmov .ne .b64 .rcx (.reg .r10), .mov .b64 .r11 (.reg .rax),
   .movImm .b64 .rdx 0, .div false .b64 (.reg .rcx), .aluImm .cmp .b64 .r10 0] ++
  (if remainder then
    [.cmov .e .b64 .rdx (.reg .r11), .mov .b64 .rax (.reg .rdx)]
   else [.movImm .b64 .rcx (BitVec.ofInt 64 (-1)), .cmov .e .b64 .rax (.reg .rcx)])

private def arithmetic : RR → Except String Code
  | .add => .ok [.alu .add .b64 .rax (.reg .r10)]
  | .sub => .ok [.alu .sub .b64 .rax (.reg .r10)]
  | .bitAnd => .ok [.alu .bitAnd .b64 .rax (.reg .r10)]
  | .bitOr => .ok [.alu .bitOr .b64 .rax (.reg .r10)]
  | .bitXor => .ok [.alu .bitXor .b64 .rax (.reg .r10)]
  | .mul => .ok [.imul .b64 .rax (.reg .r10)]
  | .divu => .ok (divide false)
  | .remu => .ok (divide true)
  | .addw => .ok ([.alu .add .b32 .rax (.reg .r10)] ++ signWord)
  | .subw => .ok ([.alu .sub .b32 .rax (.reg .r10)] ++ signWord)
  | .sltu => .ok (compare .b)
  | .slt => .ok (compare .l)
  | .sll => .ok [.mov .b64 .rcx (.reg .r10), .shift .shl .b64 .rax .cl]
  | .srl => .ok [.mov .b64 .rcx (.reg .r10), .shift .shr .b64 .rax .cl]
  | .sra => .ok [.mov .b64 .rcx (.reg .r10), .shift .sar .b64 .rax .cl]
  | .div | .rem => .error "Signed division is not used by the x86-64 SSZ backend"

private def immediateOp : RI → RR
  | .addi => .add | .andi => .bitAnd | .ori => .bitOr | .xori => .bitXor
  | .slti => .slt | .sltiu => .sltu | .addiw => .addw

private def shiftCode (op : Shift) (amount : Nat) : Code :=
  let width := if op == .slliw || op == .srliw then Size.b32 else .b64
  let kind := match op with
    | .slli | .slliw => ShiftOp.shl | .srli | .srliw => .shr | .srai => .sar
  [.shift kind width .rax (.imm (BitVec.ofNat 8 amount))] ++
    (if width == .b32 then signWord else [])

private def loadCode (op : Load) (offset : Int) : Code :=
  let address := RM.mem (.base .r11 (BitVec.ofInt 32 offset))
  match op with
  | .ld => [.mov .b64 .rax address]
  | .lwu => [.mov .b32 .rax address]
  | .lw => [.extend true .b32 .b64 .rax address]
  | .lh => [.extend true .b16 .b64 .rax address]
  | .lhu => [.extend false .b16 .b64 .rax address]
  | .lb => [.extend true .b8 .b64 .rax address]
  | .lbu => [.extend false .b8 .b64 .rax address]

private def storeSize : Store → Size
  | .sd => .b64 | .sw => .b32 | .sh => .b16 | .sb => .b8

private def condition : Branch → Cond
  | .eq => .e | .ne => .ne | .lt => .l | .ge => .ge | .ltu => .b | .geu => .ae

private def lowerScalar : LeanAsm.Symbolic.Line → Except String Code
  | .rr op dst a b => do
      return (← get .rax a) ++ (← get .r10 b) ++ (← arithmetic op) ++ (← put dst .rax)
  | .ri op dst src imm => do
      return (← get .rax src) ++ [.movImm .b64 .r10 (BitVec.ofInt 64 imm)] ++
        (← arithmetic (immediateOp op)) ++ (← put dst .rax)
  | .shift op dst src amount => do
      return (← get .rax src) ++ shiftCode op amount ++ (← put dst .rax)
  | .load op dst base offset => do
      return (← get .r11 base) ++ loadCode op offset ++ (← put dst .rax)
  | .store op src base offset => do
      return (← get .rax src) ++ (← get .r11 base) ++
        [.store (storeSize op) (.base .r11 (BitVec.ofInt 32 offset)) .rax]
  | .mv dst src => do return (← get .rax src) ++ (← put dst .rax)
  | .li dst value => do return [.movImm .b64 .rax (BitVec.ofInt 64 value)] ++ (← put dst .rax)
  | _ => .error "Expected an SSZ scalar operation"

private def lowerCode : LeanAsm.Symbolic.Line → Except String Output
  | .function name => do return [.function name] ++ (← entry)
  | .endFunction name => .ok [.endFunction name]
  | .ret => exit
  | .call name => call name
  | .branch op a b name => do
      return instructions ((← get .rax a) ++ (← get .r10 b) ++
        [.alu .cmp .b64 .rax (.reg .r10)]) ++ [.branch (condition op) name]
  | .jump name => .ok [.jump name]
  | .la dst name => do return [.leaSymbol .rax name] ++ instructions (← put dst .rax)
  | .label name => .ok [.label name]
  | .text => .ok [.text]
  | .rodata => .ok [.rodata]
  | .align n => .ok [.align n]
  | .word value => .ok [.bytes ((List.range 4).map
      (fun i => UInt8.ofNat (value.toNat / 2^(8*i) % 256))).toArray]
  | .bytes values => .ok [.bytes values.toArray]
  | op => do return instructions (← lowerScalar op)

private def stackAdjust (op : AluOp) (locals : Nat) : Except String Output := do
  let size := Asm.localSize locals
  if size ≥ 2^31 then throw "x86-64 local frame is too large"
  if size == 0 then return []
  return [.instr (.aluImm op .b64 .rsp (BitVec.ofNat 32 size))]

private def lowerLine : Asm.Line → Except String Output
  | .code op => do
      let _ ← LeanAsm.Symbolic.emitLine op
      lowerCode op
  | .frameEnter locals => stackAdjust .sub locals
  | .frameLeave locals => do return (← stackAdjust .add locals) ++ (← exit)

private abbrev Frame := Option (String × Option Nat)

private def checkFrame (frame : Frame) (line : Asm.Line) : Except String Frame := do
  match line, frame with
  | .code (.function name), none => return some (name, none)
  | .code (.endFunction name), some (owner, none) =>
      if name == owner then return none else throw "Mismatched SSZ function end"
  | .frameEnter n, some (name, none) => return some (name, some n)
  | .frameLeave n, some (name, some allocated) =>
      if n == allocated then return some (name, none) else throw "Mismatched SSZ local frame"
  | .code .ret, some (_, none) => return frame
  | .code (.function _), _ | .code (.endFunction _), _ | .code .ret, _
  | .frameEnter _, _ | .frameLeave _, _ => throw "Invalid SSZ function frame"
  | .code (.label _), _ | .code .text, _ | .code .rodata, _
  | .code (.align _), _ | .code (.word _), _ | .code (.bytes _), _ => return frame
  | _, some _ => return frame
  | _, none => throw "SSZ instruction outside a function"

/-- Lower the SSZ macro subset, not arbitrary RV64 programs. Calls take at most
    six integer arguments and return a0; caller-saved virtual values are unspecified. -/
def lower (program : Asm.Program) : Except String Output := do
  let frame ← program.foldlM checkFrame none
  if frame.isSome then throw "Unclosed SSZ function"
  return (← program.mapM lowerLine).flatten

def emit (program : Asm.Program) : Except String String := do
  LeanAsm.emitAsm "" (← lower program)

end SszAsm.Asm.X64
