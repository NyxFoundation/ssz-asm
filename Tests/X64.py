"""Execute lowering boundary cases through native x86-64 assembly."""

import tempfile
from pathlib import Path

from Runner import command, executable, run


def main() -> None:
    run(["lake", "build"])
    with tempfile.TemporaryDirectory(prefix="ssz-x64-") as directory:
        binary = executable(Path(directory), Path("Tests/X64.lean"), "Tests/X64.c", "x64", "x86_64")
        run(command(binary, "x86_64"), timeout=30)


if __name__ == "__main__":
    main()
