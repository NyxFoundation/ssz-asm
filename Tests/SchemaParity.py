"""Compare Lean declarations and compatibility to the pinned Python specification."""

import importlib.metadata
import itertools
import json
import subprocess
import tempfile
from pathlib import Path

from HashCases import Spec, declaration
from ssz.union import is_compatible

REVISION = "441165848263efe5d9f82f4e85b8e417fe8e36af"
ROOT = Path(__file__).resolve().parents[1]
ATOMS = ("boolean", "bit", "byte")


def check_reference() -> None:
    metadata = importlib.metadata.distribution("eth-ssz-specs")
    origin = json.loads(metadata.read_text("direct_url.json") or "{}")
    commit = origin.get("vcs_info", {}).get("commit_id", "")
    if REVISION not in origin.get("url", "") and commit != REVISION:
        raise SystemExit("Install the pinned reference from Tests/requirements.txt")


def as_spec(schema: tuple) -> Spec:
    kind, *args = schema
    if kind in ("vector", "list", "progressiveList"):
        return Spec(kind, args[1], as_spec(args[0]))
    if kind in ("container", "progressiveContainer"):
        active = args[0] if kind == "progressiveContainer" else ()
        return Spec(kind, fields=tuple((n, as_spec(t)) for n, t in args[-1]), active=active)
    if kind == "compatibleUnion":
        return Spec(kind, options=tuple((tag, as_spec(t)) for tag, t in args[0]))
    return Spec(kind, args[0] if args else None)


def build(schema: tuple) -> type:
    return declaration(as_spec(schema), {})


def lean(schema: tuple) -> str:
    return as_spec(schema).lean()


def declarations() -> list[tuple]:
    atoms = [(k,) for k in ATOMS] + [("uint", n) for n in (8, 16, 32, 64, 128, 256)]
    packed = [(kind, n) for kind in ("byteVector", "byteList", "bitVector", "bitList")
              for n in (0, 1, 32, 33)]
    progressive = [(kind, n) for kind in ("progressiveByteList", "progressiveBitList")
                   for n in (None, 0, 32)]
    sequences = [(kind, child, size) for kind, size in
                 (("vector", 0), ("vector", 1), ("list", 0), ("list", 32),
                  ("progressiveList", None), ("progressiveList", 32))
                 for child in (("byte",), ("uint", 8), ("boolean",), ("byteList", 32))]
    a = ("a", ("byte",))
    b = ("b", ("uint", 16))
    containers = [("container", ()), ("container", (a,)),
                  ("container", (("", ("byte",)),)),
                  ("container", (a, b)), ("container", (b, a))]
    progressive_containers = [
        ("progressiveContainer", (), ()),
        ("progressiveContainer", (True,), (a,)),
        ("progressiveContainer", (False, True), (a,)),
        ("progressiveContainer", (False, True), (b,)),
        ("progressiveContainer", (True, False, True), (a, b)),
        ("progressiveContainer", (True, False), (a,)),
        ("progressiveContainer", (True, True), (a,)),
    ]
    unions = [("compatibleUnion", options) for options in (
        (), ((0, ("byte",)),), ((128, ("byte",)),),
        ((1, ("byte",)), (127, ("uint", 8))),
        ((1, ("uint", 8)), (2, ("uint", 16))),
        ((1, ("byteList", 32)), (2, ("list", ("byte",), 32))),
        ((1, progressive_containers[1]), (2, progressive_containers[3])),
        ((1, progressive_containers[1]), (2, progressive_containers[2])),
    )]
    return atoms + packed + progressive + sequences + containers + progressive_containers + unions


def main() -> None:
    check_reference()
    schemas = declarations()
    valid = []
    lines = ["import SszAsm.Schema", "open SszAsm"]
    for index, schema in enumerate(schemas):
        try:
            reference = build(schema)
        except (ValueError, TypeError):
            reference = None
        lines.append(f"def case{index} : Schema := {lean(schema)}")
        lines.append(f"#guard case{index}.validate.isOk == {str(reference is not None).lower()}")
        if reference is not None:
            valid.append((index, reference))
    for (i, left), (j, right) in itertools.product(valid, repeat=2):
        expected = str(is_compatible(left, right)).lower()
        lines.append(f"#guard Schema.compatible case{i} case{j} == {expected}")
    subprocess.run(["lake", "build", "SszAsm.Schema"], cwd=ROOT, check=True)
    with tempfile.TemporaryDirectory(prefix="ssz-schema-parity-") as temp:
        source = Path(temp) / "Parity.lean"
        source.write_text("\n".join(lines) + "\n")
        subprocess.run(["lake", "env", "lean", str(source)], cwd=ROOT, check=True)
    print(f"{len(schemas)} declarations and {len(valid) ** 2} compatibility pairs match ssz-specs")


if __name__ == "__main__":
    main()
