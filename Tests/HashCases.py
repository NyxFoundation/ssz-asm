"""Independent pinned Python SSZ values and the matching Lean declaration corpus."""

from dataclasses import dataclass
import json
import random
import struct

import ssz


@dataclass(frozen=True)
class Spec:
    kind: str
    count: int | None = None
    element: "Spec | None" = None
    fields: tuple[tuple[str, "Spec"], ...] = ()
    active: tuple[bool, ...] = ()
    options: tuple[tuple[int, "Spec"], ...] = ()

    def lean(self) -> str:
        kind = self.kind
        if kind in ("boolean", "bit", "byte"):
            return f".{kind}"
        if kind == "uint":
            return f"(.uint {self.count})"
        if kind in ("vector", "list", "progressiveList"):
            count = self.optional() if kind == "progressiveList" else str(self.count)
            return f"(.{kind} {self.element.lean()} {count})"
        if kind == "compatibleUnion":
            entries = ", ".join(f"({tag}, {spec.lean()})" for tag, spec in self.options)
            return f"(.compatibleUnion [{entries}])"
        if kind in ("container", "progressiveContainer"):
            fields = ", ".join(f"({json.dumps(n)}, {s.lean()})" for n, s in self.fields)
            active = "[" + ", ".join(str(b).lower() for b in self.active) + "] "
            return f"(.{kind} {active if kind == 'progressiveContainer' else ''}[{fields}])"
        count = self.optional() if kind.startswith("progressive") else str(self.count)
        return f"(.{kind} {count})"

    def optional(self) -> str:
        return "none" if self.count is None else f"(some {self.count})"


U8, U16, U64, U256 = (Spec("uint", n) for n in (8, 16, 64, 256))
BYTES = Spec("byteList", 4096)
FLAGS = Spec("bitList", 4096)
RECORD = Spec("container", fields=(("number", U16), ("payload", BYTES), ("flags", FLAGS)))
SPARSE = Spec("progressiveContainer", fields=(("first", U16), ("last", BYTES)),
              active=(True,) + (False,) * 84 + (True,))
UNION = Spec("compatibleUnion", options=((1, Spec("byteList", 8)),
                                        (127, Spec("list", 8, U8))))
NESTED_UNION = Spec("compatibleUnion", options=((5, UNION), (77, UNION)))

SPECS = [
    Spec("boolean"), Spec("bit"), Spec("byte"),
    *(Spec("uint", n) for n in (8, 16, 32, 64, 128, 256)),
    *(Spec("byteVector", n) for n in (1, 31, 32, 33, 65)),
    Spec("byteList", 0), Spec("byteList", 65), BYTES,
    Spec("progressiveByteList"), Spec("progressiveByteList", 4096),
    *(Spec("bitVector", n) for n in (1, 7, 8, 255, 256, 257)),
    Spec("bitList", 0), FLAGS, Spec("progressiveBitList"), Spec("progressiveBitList", 22017),
    *(Spec("vector", 35, e) for e in (Spec("boolean"), U8, U16, U64, U256)),
    *(Spec("list", 96, e) for e in (Spec("boolean"), U8, U16, U64, U256)),
    Spec("list", 0, U16), Spec("progressiveList", element=U16),
    Spec("progressiveList", 96, U256), Spec("vector", 3, BYTES),
    Spec("list", 8, BYTES), Spec("progressiveList", element=RECORD),
    RECORD, Spec("list", 4, RECORD), Spec("container", fields=(("left", U8), ("right", U256))),
    Spec("progressiveContainer", fields=(("a", U8), ("b", U16)), active=(True, False, True)),
    SPARSE, Spec("progressiveContainer", fields=(("last", U64),), active=(False,) * 255 + (True,)),
    UNION, NESTED_UNION, Spec("list", 4, NESTED_UNION),
    Spec("container", fields=(("choice", NESTED_UNION), ("record", RECORD))),
    Spec("byteList", 1 << 200), Spec("bitList", 1 << 200), Spec("list", 1 << 200, U256),
    Spec("list", 1 << 64, RECORD), Spec("progressiveList", 0, U16),
]


def declaration(spec: Spec, cache: dict[Spec, type]) -> type:
    if spec in cache:
        return cache[spec]
    name, kind = f"Reference{len(cache)}", spec.kind
    scalar = {"boolean": ssz.Boolean, "bit": ssz.Bit, "byte": ssz.Byte}
    if kind in scalar:
        cls = scalar[kind]
    elif kind == "uint":
        cls = getattr(ssz, f"Uint{spec.count}")
    elif kind in ("vector", "list", "progressiveList"):
        base = getattr(ssz, kind[0].upper() + kind[1:])[declaration(spec.element, cache)]
        cls = type(name, (base,), {"LENGTH" if kind == "vector" else "LIMIT": spec.count})
    elif kind in ("container", "progressiveContainer"):
        attrs = {"__annotations__": {n: declaration(s, cache) for n, s in spec.fields}}
        if spec.active:
            attrs["ACTIVE_FIELDS"] = tuple(int(b) for b in spec.active)
        cls = type(name, (getattr(ssz, kind[0].upper() + kind[1:]),), attrs)
    elif kind == "compatibleUnion":
        cls = type(name, (ssz.CompatibleUnion,), {
            "OPTIONS": {tag: declaration(s, cache) for tag, s in spec.options}})
    else:
        key = "LENGTH" if kind.endswith("Vector") else "LIMIT"
        cls = type(name, (getattr(ssz, kind[0].upper() + kind[1:]),), {key: spec.count})
    cache[spec] = cls
    return cls


def generate(spec: Spec, rng: random.Random, length: int | None = None):
    kind = spec.kind
    if kind in ("boolean", "bit"):
        return bool(rng.randrange(2))
    if kind in ("uint", "byte"):
        return rng.getrandbits(spec.count if kind == "uint" else 8)
    if kind in ("container", "progressiveContainer"):
        return {n: generate(s, rng) for n, s in spec.fields}
    if kind == "compatibleUnion":
        tag, child = rng.choice(spec.options)
        return tag, generate(child, rng)
    n = length
    if n is None:
        n = spec.count if kind in ("vector", "byteVector", "bitVector") else rng.randrange(5)
        if spec.count is not None and kind not in ("vector", "byteVector", "bitVector"):
            n = min(n, spec.count)
    if "Byte" in kind or kind.startswith("byte"):
        return bytes(rng.getrandbits(8) for _ in range(n))
    if "Bit" in kind or kind.startswith("bit"):
        return [bool(rng.randrange(2)) for _ in range(n)]
    return [generate(spec.element, rng) for _ in range(n)]


def reference(spec: Spec, value, cache: dict[Spec, type]):
    cls, kind = declaration(spec, cache), spec.kind
    if kind in ("boolean", "bit", "byte", "uint", "byteVector"):
        return cls(value)
    if kind == "compatibleUnion":
        tag, held = value
        return cls(selector=ssz.Uint8(tag), data=reference(dict(spec.options)[tag], held, cache))
    if kind in ("container", "progressiveContainer"):
        return cls(**{n: reference(s, value[n], cache) for n, s in spec.fields})
    if kind in ("vector", "list", "progressiveList"):
        return cls(data=[reference(spec.element, v, cache) for v in value])
    if kind == "progressiveByteList":
        return cls(data=[ssz.Byte(v) for v in value])
    if kind in ("bitVector", "bitList", "progressiveBitList"):
        return cls(data=[ssz.Boolean(v) for v in value])
    return cls(data=value)


def node(kind: int, length: int, selector: int, payload: bytes | list[bytes]) -> bytes:
    return struct.pack("<4Q", kind, length, selector, len(payload)) + (
        b"".join(payload) if isinstance(payload, list) else payload)


def wire(spec: Spec, value) -> bytes:
    kind = spec.kind
    if kind in ("boolean", "bit", "byte", "uint"):
        width = spec.count // 8 if kind == "uint" else 1
        return node(0, width, 0, int(value).to_bytes(width, "little"))
    if kind in ("byteVector", "byteList", "progressiveByteList"):
        return node(0, len(value), 0, value)
    if kind in ("bitVector", "bitList", "progressiveBitList"):
        data = bytearray((len(value) + 7) // 8)
        for i, bit in enumerate(value):
            data[i // 8] |= int(bit) << (i % 8)
        return node(0, len(value), 0, bytes(data))
    if kind == "compatibleUnion":
        tag, child = value
        return node(1, 1, tag, [wire(dict(spec.options)[tag], child)])
    if kind in ("container", "progressiveContainer"):
        return node(1, len(spec.fields), 0, [wire(s, value[n]) for n, s in spec.fields])
    return node(1, len(value), 0, [wire(spec.element, child) for child in value])


@dataclass(frozen=True)
class Case:
    index: int
    label: str
    mode: int
    encoded: bytes
    tree: bytes = b""
    root: bytes = bytes(32)
    budget: int = 1 << 20

    def packet(self) -> bytes:
        return struct.pack("<5Q", self.index, self.mode, len(self.encoded), len(self.tree),
                           self.budget) + self.tree + self.encoded + self.root


def valid_case(index: int, value, cache: dict[Spec, type], label: str = "", budget=1 << 20) -> Case:
    spec = SPECS[index]
    expected = reference(spec, value, cache)
    return Case(index, f"{index}:{spec.kind}:{label}", 0, expected.encode_bytes(),
                wire(spec, value), bytes(expected.hash_tree_root()), budget)


def cases() -> list[Case]:
    rng, cache, result = random.Random(441165), {}, []
    for i, spec in enumerate(SPECS):
        for seed in range(4):
            value = generate(spec, rng)
            result.append(valid_case(i, value, cache, f"sample{seed}"))
        variable = spec.kind in ("list", "byteList", "bitList", "progressiveList",
                                 "progressiveByteList", "progressiveBitList")
        if variable:
            result.append(valid_case(i, generate(spec, rng, 0), cache, "empty", budget=0))
        if spec.kind in ("progressiveByteList", "progressiveBitList", "progressiveList"):
            width = 256 if spec.kind == "progressiveBitList" else 32
            if spec.element:
                width = 32 // (spec.element.count // 8) if spec.element.kind == "uint" else 1
            for chunks in (1, 2, 4, 5, 6, 20, 21, 22, 84, 85, 86):
                length = chunks * width
                if spec.count is None or length <= spec.count:
                    result.append(valid_case(i, generate(spec, rng, length), cache, f"chunks{chunks}"))
    return result + edge_cases(result, cache)


def edge_cases(valid: list[Case], cache: dict[Spec, type]) -> list[Case]:
    result = []
    for i, spec in enumerate(SPECS):
        baseline = next(c for c in valid if c.index == i)
        if declaration(spec, cache).fixed_size() is not None:
            result.append(Case(i, f"{i}:truncated", 1, baseline.encoded[:-1]))
            result.append(Case(i, f"{i}:extra", 1, baseline.encoded + b"\x00"))
        length = struct.unpack_from("<Q", baseline.tree, 8)[0]
        payload = struct.unpack_from("<Q", baseline.tree, 24)[0]
        if length and spec.kind not in ("boolean", "bit", "byte", "uint", "compatibleUnion"):
            result.append(Case(i, f"{i}:no-scratch", 2, baseline.encoded, baseline.tree, budget=0))
        if payload:
            result.append(Case(i, f"{i}:no-arena", 3, baseline.encoded, budget=0))
    for kind, payload in (("boolean", b"\x02"), ("bit", b"\xff"),
                          ("bitList", b"\x00"), ("bitList", b"\x01\x00"),
                          ("compatibleUnion", b"\x00"), ("compatibleUnion", b"\x80")):
        i = next(i for i, s in enumerate(SPECS) if s.kind == kind)
        result.append(Case(i, f"{kind}:malformed:{payload.hex()}", 1, payload))
    i = SPECS.index(Spec("list", 8, BYTES))
    for raw in (b"\x00"*4, b"\x03\x00\x00\x00", b"\x05\x00\x00\x00\x00",
                struct.pack("<II", 8, 7), struct.pack("<II", 8, 9)):
        result.append(Case(i, "malformed-list-offset", 1, raw))
    i = SPECS.index(RECORD)
    baseline = next(c for c in valid if c.index == i and len(c.encoded) > 10)
    for offset in (0, 9, 11, 0xffffffff):
        raw = baseline.encoded[:2] + struct.pack("<I", offset) + baseline.encoded[6:]
        result.append(Case(i, "malformed-container-offset", 1, raw))
    i = SPECS.index(Spec("boolean"))
    result.append(Case(i, "invalid-value-boolean", 4, b"", node(0, 1, 0, b"\x02")))
    result.append(Case(i, "invalid-null-data", 4, b"", node(0, 1, 0, b"")))
    i = SPECS.index(Spec("bitVector", 1))
    result.append(Case(i, "invalid-value-padding", 4, b"", node(0, 1, 0, b"\x80")))
    i = SPECS.index(UNION)
    result.append(Case(i, "invalid-value-selector", 4, b"",
                       node(1, 1, 0, [wire(Spec("byteList", 8), b"")])))
    i = SPECS.index(Spec("byteList", 1 << 200))
    result.append(valid_case(i, b"x", cache, "sparse-limit-32-byte-scratch", 32))
    i = SPECS.index(Spec("list", 4, RECORD))
    value = [{"number": 42, "payload": b"abc", "flags": [True, False, True]}] * 3
    tight = valid_case(i, value, cache, "nested-scratch-reuse", 224)
    result.append(tight)
    result.append(Case(i, "nested-scratch-one-byte-short", 2, tight.encoded, tight.tree, budget=223))
    verify_malformed(result, cache)
    return result


def verify_malformed(result: list[Case], cache: dict[Spec, type]) -> None:
    for case in result:
        if case.mode != 1:
            continue
        try:
            declaration(SPECS[case.index], cache).decode_bytes(case.encoded)
        except ssz.SSZError:
            continue
        raise AssertionError(f"Reference accepted an alleged malformed input: {case.label}")
