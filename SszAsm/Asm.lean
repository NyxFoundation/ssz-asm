import LeanAsm.Frontend

/-!
Compatibility surface for the original `SszAsm.Asm` namespace. The symbolic
assembly representation and GNU-as renderer now live in LeanAsm.
-/

namespace SszAsm.Asm

abbrev Reg := LeanAsm.Rv64.Reg
abbrev RR := LeanAsm.Symbolic.RR
abbrev RI := LeanAsm.Symbolic.RI
abbrev Shift := LeanAsm.Symbolic.Shift
abbrev Load := LeanAsm.Symbolic.Load
abbrev Store := LeanAsm.Symbolic.Store
abbrev Branch := LeanAsm.Symbolic.Branch
abbrev Line := LeanAsm.Symbolic.Line
abbrev Program := LeanAsm.Symbolic.Program

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
export LeanAsm.Symbolic.Line (rr ri shift load store mv li branch jump call la ret)
export LeanAsm.Symbolic.Line (label function endFunction text rodata align word bytes)
end Line

def emitReg (r : Reg) : String := toString r
abbrev validSymbol := LeanAsm.Symbolic.validSymbol
abbrev emitLine := LeanAsm.Symbolic.emitLine
abbrev emit := LeanAsm.Symbolic.emit

def emitAsm (name : String) (program : Program) : Except String String :=
  LeanAsm.emitAsm name program

def saved : List Reg :=
  [.ra, .s0, .s1, .s2, .s3, .s4, .s5, .s6, .s7, .s8, .s9, .s10, .s11]

def localSize (locals : Nat) : Nat := (locals + 15) / 16 * 16

def frameSize (locals : Nat) : Nat := localSize locals + 112

def enter (locals : Nat := 0) : Program :=
  [.ri .addi .sp .sp (-(Int.ofNat (frameSize locals)))] ++
    saved.zipIdx.map (fun (r, i) =>
      .store .sd r .sp (Int.ofNat (localSize locals + 8 * i)))

def leave (locals : Nat := 0) : Program :=
  (saved.zipIdx.map fun (r, i) =>
    .load .ld r .sp (Int.ofNat (localSize locals + 8 * i))) ++
    [.ri .addi .sp .sp (Int.ofNat (frameSize locals)), .ret]

def function (name : String) (locals : Nat) (body : Program) : Program :=
  [.function name] ++ enter locals ++ body ++ [.label (name ++ "_return")] ++
    leave locals ++ [.endFunction name]

end SszAsm.Asm
