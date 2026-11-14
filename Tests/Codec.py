"""Execute the freestanding codec acceptance tests (no Python dependencies)."""

import tempfile
from pathlib import Path

from Runner import command, executable, run, target_argument


def main() -> None:
    target = target_argument()
    run(["lake", "build"])
    with tempfile.TemporaryDirectory(prefix="ssz-codec-") as directory:
        binary = executable(Path(directory), Path("Tests/Codec.lean"), "Tests/Codec.c", "codec", target)
        run(command(binary, target), timeout=30)


if __name__ == "__main__":
    main()
