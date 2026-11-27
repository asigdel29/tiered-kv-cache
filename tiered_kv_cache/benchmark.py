"""Expose the native benchmark through the original Python command and API."""
import json
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
from ._native import artifact, run_cli


def benchmark(*, reads=128, repeats=7, page_bytes=4096, seed=42, directory=None):
    """Return paired native measurements for three reproducible workloads."""
    if min(reads, page_bytes) < 1 or repeats < 2:
        raise ValueError("use positive reads and page bytes and two or more trials")
    with TemporaryDirectory() as tmp:
        record = Path(tmp) / "benchmark.json"
        args = [artifact("kv-cache", "bin"), "bench", "--reads", str(reads),
                "--repeats", str(repeats), "--page-bytes", str(page_bytes),
                "--seed", str(seed), "--output", record]
        if directory is not None:
            args.extend(["--directory", directory])
        subprocess.run(args, check=True, stdout=subprocess.DEVNULL)
        return json.loads(record.read_text())


def main():
    """Run the native benchmark in this process."""
    run_cli("bench", sys.argv[1:])


if __name__ == "__main__":
    main()
