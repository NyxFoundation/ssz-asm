import SszAsm.Asm
import SszAsm.Schema

namespace SszAsm.Codec
open Asm

def ret (fn : String) (value : Int) : Program :=
  [.li .a0 value, .jump (fn ++ "_return")]

def errors (fn : String) : Program :=
  [.label (fn ++ "_invalid")] ++ ret fn (-1) ++
  [.label (fn ++ "_capacity")] ++ ret fn (-2) ++
  [.label (fn ++ "_overflow")] ++ ret fn (-3)

def propagate (fn : String) : Program :=
  [.branch .lt .a0 .zero (fn ++ "_return")]

def addConst (dst src : Reg) (n : Nat) : Program :=
  [.li .t6 n, .rr .add dst src .t6]

def exact (fn : String) (r : Reg) (n : Nat) : Program :=
  if n < 2^64 then [.li .t0 n, .branch .ne r .t0 (fn ++ "_invalid")]
  else [.jump (fn ++ "_invalid")]

def limit (fn : String) (r : Reg) (n : Nat) : Program :=
  if n < 2^64 then [.li .t0 n, .branch .ltu .t0 r (fn ++ "_invalid")]
  else []

def countCheck (fn : String) (r : Reg) : Schema → Program
  | .boolean | .bit | .byte => exact fn r 1
  | .uint bits => exact fn r (bits / 8)
  | .byteVector n | .bitVector n | .vector _ n => exact fn r n
  | .list _ n | .byteList n | .bitList n => limit fn r n
  | .progressiveList _ n | .progressiveByteList n | .progressiveBitList n =>
    n.map (limit fn r) |>.getD []
  | .container fs | .progressiveContainer _ fs => exact fn r fs.length
  | .compatibleUnion _ => exact fn r 1

def isBits : Schema → Bool
  | .bitVector _ | .bitList _ | .progressiveBitList _ => true
  | _ => false

def isBitList : Schema → Bool
  | .bitList _ | .progressiveBitList _ => true
  | _ => false

/-- The generic sequence/container serialization rule also covers byte aliases. -/
def compositeBound : Schema → Bool
  | .vector .. | .list .. | .progressiveList .. | .container ..
  | .progressiveContainer .. | .byteVector .. | .byteList ..
  | .progressiveByteList .. => true
  | _ => false

def checkBound (fn : String) (r : Reg) : Program :=
  [.li .t0 (2^32), .branch .geu r .t0 (fn ++ "_overflow")]

def checkedNat (fn : String) (dst : Reg) (n : Nat) : Program :=
  if n < 2^32 then [.li dst n] else [.jump (fn ++ "_overflow")]

/-- Ceil(bits/8) without overflowing the input bit count. -/
def bitBytes (dst src : Reg) : Program :=
  [.shift .srli dst src 3, .ri .andi .t0 src 7,
   .rr .sltu .t0 .zero .t0, .rr .add dst dst .t0]

def requireData (fn : String) (ptr count : Reg) (label : String) : Program :=
  [.branch .eq count .zero (fn ++ label),
   .branch .eq ptr .zero (fn ++ "_invalid"), .label (fn ++ label)]

def fixedSection (fields : List (String × Schema)) : Nat :=
  fields.foldl (fun n (_, s) => n + s.fixedSize.getD 4) 0

end SszAsm.Codec
