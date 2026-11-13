import Std

namespace SszAsm

inductive Schema where
  | boolean | bit | byte
  | uint (bits : Nat)
  | vector (element : Schema) (length : Nat)
  | list (element : Schema) (limit : Nat)
  | byteVector (length : Nat)
  | byteList (limit : Nat)
  | bitVector (length : Nat)
  | bitList (limit : Nat)
  | progressiveList (element : Schema) (limit : Option Nat := none)
  | progressiveByteList (limit : Option Nat := none)
  | progressiveBitList (limit : Option Nat := none)
  | container (fields : List (String × Schema))
  | progressiveContainer (activeFields : List Bool) (fields : List (String × Schema))
  | compatibleUnion (options : List (Nat × Schema))
  deriving Repr, Inhabited, BEq

namespace Schema

def basicSize : Schema → Option Nat
  | .boolean | .bit | .byte => some 1
  | .uint bits => some (bits / 8)
  | _ => none

def children : Schema → List Schema
  | .vector e _ | .list e _ | .progressiveList e _ => [e]
  | .container fs | .progressiveContainer _ fs => fs.map Prod.snd
  | .compatibleUnion os => os.map Prod.snd
  | _ => []

partial def fixedSize : Schema → Option Nat
  | .boolean | .bit | .byte => some 1
  | .uint bits => some (bits / 8)
  | .byteVector n => some n
  | .bitVector n => some ((n + 7) / 8)
  | .vector e n => (fixedSize e).map (· * n)
  | .container fs | .progressiveContainer _ fs =>
    fs.foldlM (fun n (_, t) => (fixedSize t).map (n + ·)) 0
  | _ => none

def childName (name : String) (index : Nat) : String := s!"{name}_child{index}"

partial def nodes (name : String) (schema : Schema) : List (String × Schema) :=
  (schema.children.zipIdx.flatMap fun (child, i) => nodes (childName name i) child) ++
    [(name, schema)]

private def byteShape : Schema → Option (Nat × Nat)
  | .byteVector n | .vector .byte n | .vector (.uint 8) n => some (0, n)
  | .byteList n | .list .byte n | .list (.uint 8) n => some (1, n)
  | .progressiveByteList _ | .progressiveList .byte _
  | .progressiveList (.uint 8) _ => some (2, 0)
  | _ => none

private def positions (active : List Bool) (fields : List (String × Schema)) :
    List (Nat × String × Schema) :=
  ((active.zipIdx.filter (·.1)).map (·.2)).zip fields |>.map
    (fun (i, name, ty) => (i, name, ty))

/-- SSZ shape compatibility is symmetric but not transitive. -/
partial def compatible (a b : Schema) : Bool :=
  if a == b then true else
  match byteShape a, byteShape b with
  | some x, some y => x == y
  | some _, none | none, some _ => false
  | none, none => match a, b with
    | .boolean, .bit | .bit, .boolean => true
    | .byte, .uint 8 | .uint 8, .byte => true
    | .uint x, .uint y => x == y
    | .bitVector x, .bitVector y | .bitList x, .bitList y => x == y
    | .progressiveBitList _, .progressiveBitList _ => true
    | .vector x n, .vector y m | .list x n, .list y m =>
      n == m && compatible x y
    | .progressiveList x _, .progressiveList y _ => compatible x y
    | .container xs, .container ys =>
      xs.length == ys.length && (xs.zip ys).all
        (fun ((n, x), (m, y)) => n == m && compatible x y)
    | .progressiveContainer ax xs, .progressiveContainer ay ys =>
      let left := positions ax xs
      let right := positions ay ys
      left.all fun (i, n, x) => right.all fun (j, m, y) =>
        (i != j || (n == m && compatible x y)) && (n != m || i == j)
    | .compatibleUnion xs, .compatibleUnion ys =>
      xs.all fun (_, x) => ys.all fun (_, y) => compatible x y
    | _, _ => false

private def check (condition : Bool) (message : String) : Except String Unit :=
  if condition then .ok () else .error message

private def validateFields (fields : List (String × Schema)) : Except String Unit := do
  check (!fields.isEmpty) "A container must declare at least one field"
  let names := fields.map Prod.fst
  check (names.eraseDups.length == names.length) "Field names must be unique"

private def validateLocal : Schema → Except String Unit
  | .uint bits => check ([8, 16, 32, 64, 128, 256].contains bits) "Invalid uint width"
  | .vector _ n | .byteVector n | .bitVector n =>
    check (n > 0) "A vector must have positive length"
  | .container fs => validateFields fs
  | .progressiveContainer active fs => do
    validateFields fs
    check (!active.isEmpty && active.length ≤ 256) "Invalid progressive layout width"
    check (active.getLast? == some true) "A progressive layout must end in an active field"
    check ((active.filter id).length == fs.length) "Progressive field count differs from layout"
  | .compatibleUnion os => do
    check (!os.isEmpty) "A compatible union must declare at least one option"
    let tags := os.map Prod.fst
    check (tags.all (fun n => 1 ≤ n && n ≤ 127)) "Union selectors must lie in 1..127"
    check (tags.eraseDups.length == tags.length) "Union selectors must be unique"
    check (os.all fun (_, a) => os.all fun (_, b) => compatible a b)
      "Union options have incompatible shapes"
  | _ => .ok ()

/-- Validate every declaration, including all crossing union option pairs. -/
partial def validate (schema : Schema) : Except String Unit := do
  validateLocal schema
  for child in schema.children do
    validate child
    check (child.fixedSize != some 0) "An element cannot have an empty fixed encoding"

end Schema
end SszAsm
