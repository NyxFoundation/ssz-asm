"""Deterministic mutation tests of generated decoders against ssz-specs."""

import random
import struct
import subprocess
import tempfile
from pathlib import Path

import ssz
from ssz.uint import BaseUint

from Runner import command, executable, run, target_argument
from SchemaParity import build, check_reference, declarations, lean


def sample(cls: type, rng: random.Random):
    if issubclass(cls, ssz.Boolean):
        return cls(rng.randrange(2))
    if issubclass(cls, BaseUint):
        return cls(rng.getrandbits(cls.BITS))
    if issubclass(cls, ssz.CompatibleUnion):
        tag = rng.choice(list(cls.OPTIONS))
        return cls(selector=tag, data=sample(cls.OPTIONS[tag], rng))
    if issubclass(cls, (ssz.Container, ssz.ProgressiveContainer)):
        return cls(**{name: sample(field.annotation, rng)
                      for name, field in cls.model_fields.items()})
    fixed = getattr(cls, "LENGTH", None)
    limit = getattr(cls, "LIMIT", None)
    length = fixed if fixed is not None else rng.randrange(min(limit or 0, 4) + 1)
    if fixed is None and limit is None:
        length = rng.randrange(5)
    if issubclass(cls, ssz.ByteVector):
        return cls(rng.randbytes(length))
    if issubclass(cls, ssz.ByteList):
        return cls(data=rng.randbytes(length))
    if issubclass(cls, (ssz.BitVector, ssz.BitList, ssz.ProgressiveBitList)):
        return cls(data=[rng.randrange(2) for _ in range(length)])
    return cls(data=[sample(cls.ELEMENT_TYPE, rng) for _ in range(length)])


def variants(data: bytes, rng: random.Random) -> set[bytes]:
    result = {data, b"", data + b"\x00", data + b"\xff"}
    for _ in range(40):
        if data:
            cut = rng.randrange(len(data))
            result.add(data[:cut])
            altered = bytearray(data)
            altered[cut] ^= 1 << rng.randrange(8)
            result.add(bytes(altered))
            result.add(data[:cut] + rng.randbytes(1) + data[cut:])
        result.add(rng.randbytes(rng.randrange(40)))
    return result


def schema_cases(rng: random.Random) -> tuple[list[tuple], list[tuple[int, bytes, int]]]:
    schemas, cases = [], []
    record = ("container", (("id", ("uint", 64)), ("items", ("list", ("byteList", 8), 8)),
                            ("bits", ("bitList", 256))))
    candidates = declarations() + [record, ("list", record, 8),
        ("vector", ("list", ("byteList", 8), 8), 3),
        ("compatibleUnion", ((1, ("compatibleUnion", ((2, ("uint", 16)),))),))]
    for schema in candidates:
        try:
            cls = build(schema)
        except (ValueError, TypeError):
            continue
        index = len(schemas)
        schemas.append(schema)
        encoded = set()
        for _ in range(5):
            encoded.update(variants(sample(cls, rng).encode_bytes(), rng))
        for data in sorted(encoded):
            try:
                value = cls.decode_bytes(data)
            except (ValueError, TypeError):
                expected = 1
            else:
                if value.encode_bytes() != data:
                    raise AssertionError("Reference accepted a non-canonical encoding")
                expected = 0
            cases.append((index, data, expected))
    return schemas, cases


def emit_fixtures(temp: Path, schemas: list[tuple]) -> None:
    definitions = ",\n".join(f'("Fuzz{i}", {lean(t)})' for i, t in enumerate(schemas))
    source = """import SszAsm
open SszAsm

def main (args : List String) : IO Unit := do
  let target ← IO.ofExcept (Target.parse (args.headD "rv64"))
  let schemas : List (String × Schema) := [
""" + definitions + """
  ]
  for (_, schema) in schemas do
    match schema.validate with
    | .ok () => pure ()
    | .error e => throw (IO.userError e)
  let program := Runtime.program ++ schemas.flatMap fun (name, schema) =>
    (Schema.nodes name schema).flatMap fun (n, t) => Codec.compileNode n t
  match emitProgram program target with
  | .ok text => (← IO.getStdout).putStr text
  | .error e => throw (IO.userError e)
"""
    (temp / "Generate.lean").write_text(source)
    header = "\n".join(f"SSZ_DECLARE(Fuzz{i});" for i in range(len(schemas)))
    header += "\nstatic const Operations operations[] = {\n"
    header += ",\n".join(f"{{Fuzz{i}_serialize, Fuzz{i}_deserialize}}"
                         for i in range(len(schemas))) + "\n};\n"
    (temp / "fuzz_cases.h").write_text(header)


def main() -> None:
    check_reference()
    target = target_argument()
    run(["lake", "build"])
    schemas, cases = schema_cases(random.Random(20261112))
    wire = b"".join(struct.pack("<II", i, len(data)) + data for i, data, _ in cases)
    with tempfile.TemporaryDirectory(prefix="ssz-codec-fuzz-") as directory:
        temp = Path(directory)
        emit_fixtures(temp, schemas)
        binary = executable(temp, temp / "Generate.lean", "Tests/CodecFuzz.c", "fuzz", target)
        result = subprocess.run(command(binary, target), input=wire, capture_output=True,
                                check=True, timeout=90)
    if len(result.stdout) != len(cases):
        raise AssertionError("The decoder did not return one result per input")
    for actual, (index, data, expected) in zip(result.stdout, cases, strict=True):
        if actual != expected:
            raise AssertionError(f"Schema {index}: {data.hex()} returned {actual}, expected {expected}")
    print(f"{len(cases)} {target} acceptance/roundtrip mutation cases match ssz-specs")


if __name__ == "__main__":
    main()
