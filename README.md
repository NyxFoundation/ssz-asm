# ssz-asm

A Lean 4 macro-assembly library for SSZ on little-endian RISC-V RV64IM and
Linux x86-64. It generates `serialize`, `deserialize`, and `hash_tree_root`
functions using the RISC-V LP64 or System V AMD64 C ABI. No dedicated CLI,
zkVM, malloc, or crypto accelerator is required.

**Experimental and unproved.** Execution tests are not Lean correctness proofs.
Upstream evm-asm proofs do not apply to this implementation.

## Generate and run

Install [elan](https://lean-lang.org/install/). Lean 4.33.0 and the `LeanAsm`
assembly foundation are commit/version-pinned.

### Linux x86-64

On an x86-64 host with GCC and GNU binutils:

```sh
lake build
lake env lean --run Examples/Generate.lean x86_64
gcc -O1 -Wall -Wextra -Werror -fPIE -pie -Iinclude -I.build Examples/Message.c .build/message.s -o .build/message-x86_64
.build/message-x86_64
```

This uses scalar instructions only, with no SIMD or SHA extension requirement.
The initial backend uses stack slots for virtual registers; it is not optimized
for throughput. Windows and 32-bit x86 are not supported.

### RISC-V RV64IM

Install GNU RISC-V binutils, Clang with a RISC-V target, and QEMU user-mode RISC-V:

```sh
lake build
lake env lean --run Examples/Generate.lean
riscv64-unknown-elf-as -march=rv64im -mabi=lp64 .build/message.s -o .build/message.o
clang --target=riscv64-unknown-elf -march=rv64im -mabi=lp64 -ffreestanding -fno-builtin -fno-stack-protector -O1 -Iinclude -I.build -c Examples/Message.c -o .build/caller.o
riscv64-unknown-elf-as -march=rv64im -mabi=lp64 Examples/Start.s -o .build/start.o
riscv64-unknown-elf-ld -static -e _start .build/message.o .build/caller.o .build/start.o -o .build/message.elf
qemu-riscv64 .build/message.elf
```

Exit zero means the C example encoded and decoded a message with matching roots.
Lean constructs typed instructions and labels; GNU binutils assembles them.
GCC or Clang builds only the C caller. The generated library has no syscalls;
the freestanding RISC-V example startup uses one to exit.

## Lean API

```lean
import SszAsm
open SszAsm

def message : Schema :=
  .container [("id", .uint 64), ("payload", .byteList 4096)]

#check compile       -- List (String × Schema) → Except String Asm.Program
#check emitAssembly  -- List (String × Schema) → Target → Except String String
#check emitHeader    -- List (String × Schema) → Except String String

#eval emitHeader [("Message", message)]
#eval (emitAssembly [("Message", message)] .x86_64).isOk
```

Pass all public schemas to one emission call so shared routines occur once.
Names must be ASCII identifiers; `ssz_` is reserved. Public/child name collisions
are rejected. [Examples/Generate.lean](Examples/Generate.lean) writes the assembly
and C declarations through these APIs, without a product CLI. Its optional
`rv64` or `x86_64` argument selects the target; the default remains `rv64`.
The C header and value layout are identical for both targets.

## C ABI

Include `include/ssz_asm.h` and the generated header. Each name exports:

- `name_serialize(value, output, capacity)`: byte count or negative error.
- `name_deserialize(input, length, value, arena)`: zero or negative error.
- `name_hash_tree_root(value, output32, scratch)`: zero or negative error.

Errors are `SSZ_INVALID`, `SSZ_NO_SPACE`, and `SSZ_OVERFLOW`.
Values use byte buffers or child-value arrays, not inferred native C structs.
Decode copies leaves into an 8-byte-aligned caller arena. Hash restores the
scratch descriptor, but scratch contents are unspecified. Discard output on
error; reset the decode arena after failure.

See [Architecture and ABI](docs/architecture.md) for representations and pointer
preconditions, and [Examples/Message.c](Examples/Message.c) for value construction.

## Specification and scope

The reference is [ethereum/ssz-specs at `4411658`](https://github.com/ethereum/ssz-specs/tree/441165848263efe5d9f82f4e85b8e417fe8e36af).
All type families are included: Boolean, Bit, Byte, Uint8/16/32/64/128/256,
Vector, List, ByteVector/List, BitVector/List, Container, ProgressiveList,
ProgressiveByteList, ProgressiveBitList, ProgressiveContainer, and CompatibleUnion.
Runtime lengths are 64-bit; serialized sequences/containers must be below 2^32.
Sparse declared capacities remain Lean naturals. Generalized indices and Merkle
proof APIs are excluded.

The instruction representation/emitter is shared through `NyxFoundation/LeanAsm`.
`SszAsm.Asm.Program` adds target-owned frame directives to LeanAsm's scalar
symbolic vocabulary. Its `EmitAsm` instance emits RISC-V;
`emitProgram program .x86_64` lowers to LeanAsm's typed x86-64 symbolic program.
Neither backend claims fixed-instruction lowering for a translation unit with
labels and data sections. LeanAsm adapts
the reusable macro-assembly design from evm-asm at `7e65e4d`, not its
EVM programs or zkVM environment. [NOTICE.md](NOTICE.md) records the source pins
and licensing.

## Tests

Install Python 3.12+ and [uv](https://docs.astral.sh/uv/), then the pinned reference:

```sh
uv venv .venv
uv pip install --python .venv/bin/python -r Tests/requirements.txt
lake env lean Tests/Asm.lean
lake env lean Tests/Declarations.lean
lake env lean --run Tests/Public.lean
.venv/bin/python Tests/SchemaParity.py
```

On Linux x86-64, run the native lowering and SSZ suites:

```sh
.venv/bin/python Tests/X64.py
.venv/bin/python Tests/Codec.py --target x86_64
.venv/bin/python Tests/CodecFuzz.py --target x86_64
.venv/bin/python Tests/Hash.py --target x86_64
```

Run the same SSZ suites under RISC-V QEMU with `--target rv64` (the default).
Set `QEMU_RISCV64=/path/to/qemu-riscv64` if QEMU is not on PATH.
Tests execute generated assembly and compare encoding, decoded structure, roots,
rejections, and compatibility against the pinned reference. They include
offsets, padding, arena overflow, scratch reuse, callee-saved registers,
SHA-256 known answers, progressive boundaries, and sparse capacities up to 2^200.
The native lowering suite also exercises arithmetic edge cases, signed word
extension, unaligned loads/stores, stack alignment, and six-argument nested calls.
Test artifacts are temporary; no assembly snapshots are required.
