"""Execute generated RV64IM against pinned Python SSZ; install Tests/requirements.txt first."""

import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile

from HashCases import SPECS, cases
from SchemaParity import check_reference
from ssz.trees import merkleize, merkleize_progressive


def run(command: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(command, check=True, **kwargs)


def runtime_vectors(temp: Path) -> None:
    data = bytes((i * 17 + i // 13) & 255 for i in range(86 * 32))
    chunks = [data[i:i + 32] for i in range(0, len(data), 32)]
    trials = [(n, depth) for n, depth in ((0, 0), (0, 1), (0, 64), (0, 200),
              (1, 0), (1, 64), (1, 200), (2, 1), (3, 2), (5, 3), (21, 5), (85, 7), (86, 7))]
    trials += [(n, -1) for n in (0, 1, 2, 5, 6, 21, 22, 85, 86)]
    roots = [bytes(merkleize_progressive(chunks[:n]) if depth < 0 else
                   merkleize(chunks[:n], 1 << depth)) for n, depth in trials]
    arrays = ",\n".join("{" + ",".join(str(b) for b in root) + "}" for root in roots)
    (temp / "hash_runtime_vectors.h").write_text(
        f"#define MERKLE_CASES {len(trials)}\n" +
        "static const unsigned merkle_counts[] = {" + ",".join(str(n) for n, _ in trials) + "};\n" +
        "static const int merkle_depths[] = {" + ",".join(str(d) for _, d in trials) + "};\n" +
        "static const uint8_t merkle_roots[][32] = {" + arrays + "};\n")


def emit_test_sources(temp: Path) -> Path:
    entries = ",\n".join(f'  ("fixture{i}", {s.lean()})' for i, s in enumerate(SPECS))
    lean = temp / "HashEmit.lean"
    lean.write_text('''import SszAsm.Hash
import SszAsm.Codec
import SszAsm.Runtime
open SszAsm
set_option maxRecDepth 100000
def fixtures : List (String × Schema) := [
''' + entries + ''']
def main : IO Unit := do
  for (_, schema) in fixtures do
    if let .error e := schema.validate then throw (IO.userError e)
  let code := Runtime.program ++ Hash.runtime ++ fixtures.flatMap fun (n, s) =>
    (Schema.nodes n s).flatMap fun (name, schema) =>
      Codec.compileNode name schema ++ Hash.compileNode name schema
  match Asm.emit code with
  | .error e => throw (IO.userError e)
  | .ok asm => (← IO.getStdout).putStr asm
''')
    declarations = "\n".join(f"SSZ_DECLARE(fixture{i});" for i in range(len(SPECS)))
    entries = ",\n".join(
        f"  {{fixture{i}_serialize, fixture{i}_deserialize, fixture{i}_hash_tree_root}}"
        for i in range(len(SPECS)))
    (temp / "hash_declarations.h").write_text('''typedef struct {
  int64_t (*encode)(const ssz_value *, uint8_t *, uint64_t);
  int64_t (*decode)(const uint8_t *, uint64_t, ssz_value *, ssz_arena *);
  int64_t (*hash)(const ssz_value *, uint8_t *, ssz_arena *);
} Operations;
''' + declarations + f"\n#define OPERATION_COUNT {len(SPECS)}\n" +
        "static const Operations operations[] = {\n" + entries + "\n};\n")
    return lean


def executable(temp: Path, source: Path, harness: str, stem: str) -> Path:
    asm, obj, test_obj = (temp / f"{stem}{suffix}" for suffix in (".s", ".o", "_test.o"))
    with asm.open("w") as output:
        run(["lake", "env", "lean", "--run", str(source)], stdout=output)
    run(["riscv64-unknown-elf-as", "-march=rv64im", "-mabi=lp64", str(asm), "-o", str(obj)])
    run(["clang", "--target=riscv64-unknown-elf", "-march=rv64im", "-mabi=lp64",
         "-ffreestanding", "-fno-stack-protector", "-fno-builtin", "-O1", "-Wall", "-Wextra",
         "-Werror", "-Iinclude", f"-I{temp}", "-c", harness, "-o", str(test_obj)])
    binary = temp / stem
    run(["riscv64-unknown-elf-ld", "-static", "-e", "_start", str(obj), str(test_obj),
         "-o", str(binary)])
    return binary


def main() -> None:
    os.chdir(Path(__file__).resolve().parents[1])
    check_reference()
    qemu = os.environ.get("QEMU_RISCV64") or shutil.which("qemu-riscv64")
    if not qemu:
        raise SystemExit("Install qemu-riscv64 on PATH or set QEMU_RISCV64")
    run(["lake", "build", "SszAsm.Hash", "SszAsm.Codec", "SszAsm.Runtime"])
    corpus = cases()
    packet = struct.pack("<Q", len(corpus)) + b"".join(c.packet() for c in corpus)
    with tempfile.TemporaryDirectory(prefix="ssz-hash-") as directory:
        temp = Path(directory)
        runtime_vectors(temp)
        kat = executable(temp, Path("Tests/HashRuntime.lean"), "Tests/HashRuntime.c", "runtime")
        run([qemu, str(kat)], timeout=30)
        print("SHA-256 known answers, 22 Merkle vectors, and ABI checks passed", flush=True)
        binary = executable(temp, emit_test_sources(temp), "Tests/HashHarness.c", "differential")
        result = subprocess.run([qemu, str(binary)], input=packet, capture_output=True, timeout=120)
        print(result.stdout.decode(), end="", flush=True)
        if result.returncode:
            match = re.search(rb"FAIL case (\d+)", result.stdout)
            label = corpus[int(match[1])].label if match else "unknown case"
            raise SystemExit(f"QEMU failed ({result.returncode}): {label}\n{result.stderr.decode()}")


if __name__ == "__main__":
    main()
