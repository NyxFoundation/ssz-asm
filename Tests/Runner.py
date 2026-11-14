"""Build the same freestanding acceptance harness for either supported target."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def run(command: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(command, cwd=ROOT, check=True, **kwargs)


def target_argument() -> str:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", choices=("rv64", "x86_64"), default="rv64")
    return parser.parse_args().target


def command(binary: Path, target: str) -> list[str]:
    if target == "x86_64":
        return [str(binary)]
    qemu = os.environ.get("QEMU_RISCV64") or shutil.which("qemu-riscv64")
    if not qemu:
        raise SystemExit("Install qemu-riscv64 on PATH or set QEMU_RISCV64")
    return [qemu, str(binary)]


def executable(temp: Path, source: Path, harness: str, stem: str, target: str) -> Path:
    asm, obj, caller, start = (temp / f"{stem}{suffix}"
                               for suffix in (".s", ".o", "_test.o", "_start.o"))
    with asm.open("w") as output:
        run(["lake", "env", "lean", "--run", str(source), target], stdout=output)
    compiler = ["gcc"] if target == "x86_64" else [
        "clang", "--target=riscv64-unknown-elf", "-march=rv64im", "-mabi=lp64"]
    if target == "x86_64":
        run(["gcc", "-c", str(asm), "-o", str(obj)])
    else:
        run(["riscv64-unknown-elf-as", "-march=rv64im", "-mabi=lp64", str(asm), "-o", str(obj)])
    run(compiler + ["-ffreestanding", "-fno-builtin", "-fno-stack-protector",
        "-fomit-frame-pointer", "-O1", "-Wall", "-Wextra", "-Werror",
        "-Iinclude", "-ITests", f"-I{temp}", "-c", harness, "-o", str(caller)])
    run(compiler + ["-c", "Tests/Start.S", "-o", str(start)])
    binary = temp / stem
    linker = (["gcc", "-nostdlib", "-static", "-no-pie"] if target == "x86_64"
              else ["riscv64-unknown-elf-ld", "-static"])
    run(linker + ["-e", "_start", str(obj), str(caller), str(start), "-o", str(binary)])
    return binary
