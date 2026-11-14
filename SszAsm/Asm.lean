import LeanAsm.Frontend
import LeanAsm.ABI.LP64

/-! SSZ register-machine code with explicit, target-owned stack frames.
    Scalar operations use LeanAsm's RV64-shaped symbolic vocabulary. -/

namespace SszAsm.Asm

abbrev Reg := LeanAsm.Rv64.Reg
abbrev RR := LeanAsm.Symbolic.RR
abbrev RI := LeanAsm.Symbolic.RI
abbrev Shift := LeanAsm.Symbolic.Shift
abbrev Load := LeanAsm.Symbolic.Load
abbrev Store := LeanAsm.Symbolic.Store
abbrev Branch := LeanAsm.Symbolic.Branch
inductive Line where
  | code (line : LeanAsm.Symbolic.Line)
  | frameEnter (locals : Nat)
  | frameLeave (locals : Nat)
  deriving Repr

abbrev Program := List Line

namespace Reg
export LeanAsm.Rv64.Reg (x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 x10 x11 x12 x13 x14 x15)
export LeanAsm.Rv64.Reg (x16 x17 x18 x19 x20 x21 x22 x23 x24 x25 x26 x27 x28 x29 x30 x31)
export LeanAsm.Rv64.Reg (zero ra sp gp tp t0 t1 t2 s0 fp s1 a0 a1 a2 a3 a4 a5 a6 a7)
export LeanAsm.Rv64.Reg (s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 t3 t4 t5 t6 toNat)
end Reg

namespace RR
export LeanAsm.Symbolic.RR (add sub mul div divu rem remu sltu slt sll srl sra)
export LeanAsm.Symbolic.RR (bitAnd bitOr bitXor addw subw)
end RR

namespace RI
export LeanAsm.Symbolic.RI (addi andi ori xori slti sltiu addiw)
end RI

namespace Shift
export LeanAsm.Symbolic.Shift (slli srli srai slliw srliw)
end Shift

namespace Load
export LeanAsm.Symbolic.Load (ld lw lwu lh lhu lb lbu)
end Load

namespace Store
export LeanAsm.Symbolic.Store (sd sw sh sb)
end Store

namespace Branch
export LeanAsm.Symbolic.Branch (eq ne lt ge ltu geu)
end Branch

namespace Line
def rr (op : RR) (dst a b : Reg) : Line := .code (.rr op dst a b)
def ri (op : RI) (dst src : Reg) (imm : Int) : Line := .code (.ri op dst src imm)
def shift (op : Shift) (dst src : Reg) (amount : Nat) : Line :=
  .code (.shift op dst src amount)
def load (op : Load) (dst base : Reg) (offset : Int) : Line := .code (.load op dst base offset)
def store (op : Store) (src base : Reg) (offset : Int) : Line := .code (.store op src base offset)
def mv (dst src : Reg) : Line := .code (.mv dst src)
def li (dst : Reg) (value : Int) : Line := .code (.li dst value)
def branch (op : Branch) (a b : Reg) (target : String) : Line := .code (.branch op a b target)
def jump (target : String) : Line := .code (.jump target)
def call (target : String) : Line := .code (.call target)
def la (dst : Reg) (symbol : String) : Line := .code (.la dst symbol)
def ret : Line := .code .ret
def label (name : String) : Line := .code (.label name)
def function (name : String) : Line := .code (.function name)
def endFunction (name : String) : Line := .code (.endFunction name)
def text : Line := .code .text
def rodata : Line := .code .rodata
def align (power : Nat) : Line := .code (.align power)
def word (value : UInt32) : Line := .code (.word value)
def bytes (values : List UInt8) : Line := .code (.bytes values)
end Line

abbrev emitReg : Reg → String := toString
abbrev validSymbol := LeanAsm.Symbolic.validSymbol
def saved : List Reg :=
  LeanAsm.ABI.LP64.calleeSaved

abbrev localSize : Nat → Nat :=
  LeanAsm.ABI.LP64.localSize

abbrev frameSize : Nat → Nat :=
  LeanAsm.ABI.LP64.frameSize

private def enterRv64 (locals : Nat) : LeanAsm.Symbolic.Program :=
  [.ri .addi .sp .sp (-(Int.ofNat (frameSize locals)))] ++
    saved.zipIdx.map (fun (r, i) =>
      .store .sd r .sp (Int.ofNat (localSize locals + 8 * i)))

private def leaveRv64 (locals : Nat) : LeanAsm.Symbolic.Program :=
  (saved.zipIdx.map fun (r, i) =>
    .load .ld r .sp (Int.ofNat (localSize locals + 8 * i))) ++
    [.ri .addi .sp .sp (Int.ofNat (frameSize locals)), .ret]

def toRv64 (program : Program) : LeanAsm.Symbolic.Program :=
  program.flatMap fun line => match line with
    | .code op => [op]
    | .frameEnter locals => enterRv64 locals
    | .frameLeave locals => leaveRv64 locals

def emitLine (line : Line) : Except String String := do
  return String.intercalate "\n" (← (toRv64 [line]).mapM LeanAsm.Symbolic.emitLine)

def emit (program : Program) : Except String String := LeanAsm.Symbolic.emit (toRv64 program)

instance : LeanAsm.EmitAsm Program where
  emit _ := emit

def emitAsm (name : String) (program : Program) : Except String String :=
  LeanAsm.emitAsm name program

def enter (locals : Nat := 0) : Program := [.frameEnter locals]
def leave (locals : Nat := 0) : Program := [.frameLeave locals]

def function (name : String) (locals : Nat) (body : Program) : Program :=
  [.function name] ++ enter locals ++ body ++ [.label (name ++ "_return")] ++
    leave locals ++ [.endFunction name]

end SszAsm.Asm
