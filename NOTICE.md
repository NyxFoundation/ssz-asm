# Third-party provenance

The RV64 instruction representation and GNU-as rendering in `SszAsm/Asm.lean`
adapt `EvmAsm/Codegen/Emit.lean` from
[Verified-zkEVM/evm-asm](https://github.com/Verified-zkEVM/evm-asm/tree/7e65e4d024718f704226cd795f3d03d4e9aafe13).
Copyright (c) 2026 ZkSecurity.

Schema, codec, and Merkleization rules follow
[ethereum/ssz-specs](https://github.com/ethereum/ssz-specs/tree/441165848263efe5d9f82f4e85b8e417fe8e36af).
Tests install that exact source as an independent Python oracle.
Copyright (c) 2025 Ethereum Foundation.

Both sources use the MIT license. Their notices and common license terms are
retained in [LICENSE](LICENSE). The Lean assembly implementation is maintained
here and does not inherit upstream execution semantics or correctness proofs.
