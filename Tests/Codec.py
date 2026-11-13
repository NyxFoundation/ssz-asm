"""Build and execute the freestanding codec acceptance tests (no Python dependencies)."""

import os
import shutil
import subprocess
import tempfile
from pathlib import Path


def run(command: list[str], **kwargs: object) -> None:
    subprocess.run(command, check=True, **kwargs)


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    os.chdir(root)
    qemu = os.environ.get("QEMU_RISCV64") or shutil.which("qemu-riscv64")
    if not qemu:
        raise SystemExit("Set QEMU_RISCV64 to an installed qemu-riscv64 executable")
    run(["lake", "build", "SszAsm.Codec", "SszAsm.Runtime"])
    with tempfile.TemporaryDirectory(prefix="ssz-codec-") as directory:
        temp = Path(directory)
        asm, obj = temp / "codec.s", temp / "codec.o"
        harness, executable = temp / "harness.o", temp / "test"
        with asm.open("w") as output:
            run(["lake", "env", "lean", "--run", "Tests/Codec.lean"], stdout=output)
        run(["riscv64-unknown-elf-as", "-march=rv64im", "-mabi=lp64", str(asm), "-o", str(obj)])
        run(["clang", "--target=riscv64-unknown-elf", "-march=rv64im", "-mabi=lp64",
             "-ffreestanding", "-fno-stack-protector", "-fno-builtin", "-O1",
             "-Wall", "-Wextra", "-Werror", "-Iinclude", "-c", "Tests/Codec.c", "-o", str(harness)])
        run(["riscv64-unknown-elf-ld", "-static", "-e", "_start", str(obj), str(harness),
             "-o", str(executable)])
        run([qemu, str(executable)], timeout=30)


if __name__ == "__main__":
    main()
