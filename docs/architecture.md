---
title: Architecture and ABI
last_updated: 2026-11-12
tags:
  - architecture
  - abi
  - riscv
  - ssz
---

# Architecture and ABI

## Boundaries

`Schema` represents all SSZ type families, including Progressive types and
CompatibleUnion. A declaration is checked before emitting assembly.
`Asm.Program` is a typed list of symbolic instruction/directive nodes; rendering
checks immediates and identifiers. GNU binutils resolves symbolic labels.

Each named schema produces three functions under the little-endian RISC-V
LP64 C ABI. The public C structures and declaration macro are in
`include/ssz_asm.h`. Callee-saved registers and 16-byte stack alignment are
preserved. The library neither allocates with malloc nor performs syscalls.

- `name_serialize(value, output, capacity)`: encoded byte count on success.
- `name_deserialize(input, length, value, arena)`: zero on success.
- `name_hash_tree_root(value, output32, scratch)`: zero on success.

Negative returns are `SSZ_INVALID` (-1), `SSZ_NO_SPACE` (-2), or
`SSZ_OVERFLOW` (-3). Sequence and container encodings must fit the
specification's exclusive 2^32 ceiling. Bitfields and unions follow their
separate upstream rules. Hashing is not subject to an encoded-size ceiling.

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
