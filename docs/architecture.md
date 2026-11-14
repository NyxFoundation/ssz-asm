---
title: Architecture and ABI
last_updated: 2026-11-14
tags:
  - architecture
  - abi
  - riscv
  - x86-64
  - ssz
---

# Architecture and ABI

## Boundaries

`Schema` represents all SSZ type families, including Progressive types and
CompatibleUnion. A declaration is checked before emitting assembly.
`Asm.Program` is a typed list of scalar operations, symbolic directives, and
explicit frame entry/exit nodes. Its scalar vocabulary comes from LeanAsm's
RV64 symbolic layer. `emitAssembly schemas target` selects `.rv64` (the default)
or `.x86_64`; both use the same codec, SHA-256, and Merkle routines.
Rendering checks immediates and identifiers. GNU binutils resolves labels.

Each named schema produces three functions under the little-endian RISC-V
LP64 C ABI or the Linux x86-64 System V AMD64 ABI. The public C structures and declaration macro are in
`include/ssz_asm.h`. Callee-saved registers and 16-byte stack alignment are
preserved. The library neither allocates with malloc nor performs syscalls.

- `name_serialize(value, output, capacity)`: encoded byte count on success.
- `name_deserialize(input, length, value, arena)`: zero on success.
- `name_hash_tree_root(value, output32, scratch)`: zero on success.

Negative returns are `SSZ_INVALID` (-1), `SSZ_NO_SPACE` (-2), or
`SSZ_OVERFLOW` (-3). Sequence and container encodings must fit the
specification's exclusive 2^32 ceiling. Bitfields and unions follow their
separate upstream rules. Hashing is not subject to an encoded-size ceiling.

## Backend boundary

`Asm.toRv64` expands frame directives using LeanAsm's LP64 helpers and returns
`LeanAsm.Symbolic.Program`. `Asm.X64.lower` returns
`LeanAsm.X64.Symbolic.Program`; LeanAsm emits its typed instructions in GNU
Intel syntax. Neither path claims fixed-instruction lowering of code plus data.

The x86-64 backend keeps virtual registers in a 256-byte invocation-local bank
addressed by RBP. RSP addresses a separate 16-byte-rounded local area. LeanAsm's
SysV helpers preserve the six native callee-saved registers and align RSP before
calls. Total frame allocation is 312 bytes plus the rounded local area, excluding
the call's return address. Recursive calls have independent banks; no heap or
shared register state is used. This initial backend favors correctness over
register-allocation performance.

Calls marshal a0–a5 to the six SysV integer argument registers and return RAX to
a0. Only a0 is a return value; caller-saved virtual values must not be relied on
after calls. Frame directives own stack adjustment. Arbitrary RV64 programs,
ra/gp/tp, a6/a7, and signed division are rejected rather than approximated.
The SSZ generators do not use those operations. Word arithmetic and shifts
retain RV-style 32-bit sign extension, and unsigned division by zero retains
its defined RV result. Constants use RIP-relative addresses and four-byte
little-endian words, including in PIE executables.

The x86-64 target is scalar, Linux/System V only. Windows, 32-bit x86, SIMD
optimization, and correctness proofs are not included. Execution tests check
both targets against the same pinned SSZ reference; they are not proofs.

## Value representation

A value occupies 24 bytes: a data pointer, a 64-bit length, and a 64-bit selector.

| Schema | data | length | selector |
| --- | --- | --- | --- |
| Boolean, Bit, Byte, Uint | little-endian bytes | exact scalar byte width | ignored |
| ByteVector, ByteList, ProgressiveByteList | byte buffer | byte count | ignored |
| BitVector, BitList, ProgressiveBitList | packed bits, low bit first, no delimiter | bit count | ignored |
| Vector, List, ProgressiveList | contiguous 24-byte child values | element count | ignored |
| Container, ProgressiveContainer | contiguous child values in field order | field count | ignored |
| CompatibleUnion | one child value | 1 | declared option selector |

Bitfield padding above the bit count must be zero. BitList delimiters exist
only in serialized bytes, not in this value representation.
Even basic-element Vectors and Lists use child values; the Byte variants use
compact byte buffers.

Deserialization allocates child arrays and copies leaf bytes into the supplied
arena. The decoded value does not borrow its input. The arena initially points
to an 8-byte-aligned writable buffer and tracks remaining bytes. It advances as
storage is consumed. Hashing restores the scratch arena descriptor on both
success and failure, but may overwrite scratch bytes. Scratch and decoded
storage belong to the caller.

## Memory contract

The caller supplies valid pointers spanning the declared lengths, a valid
writable result, enough machine stack for the schema nesting, and disjoint input,
output, value-tree, and arena regions. Null data is permitted only for empty
data. The value graph must be acyclic and must follow the schema's node layout.
These are ordinary C pointer preconditions, not properties that assembly can
establish. Lengths, limits, offsets, selectors, scalar encodings, bit padding,
and arena capacities are checked by the generated functions.

On failure, output and arena contents may be partially modified. A caller
discards the result and reinitializes a decode arena before reuse.
