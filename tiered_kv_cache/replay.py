"""Expose the native replay through the original Python command and API."""
import json
import subprocess
import sys
from ._native import artifact, run_cli


def replay(directory=None, rounds=1):
    """Return the native replay record as a Python dictionary."""
    if rounds < 1:
        raise ValueError("rounds must be positive")
    args = [artifact("kv-cache", "bin"), "replay", "--rounds", str(rounds)]
    if directory is not None:
        args.extend(["--directory", directory])
    return json.loads(subprocess.check_output(args))


def main():
    """Run the native replay in this process."""
    run_cli("replay", sys.argv[1:])


if __name__ == "__main__":
    main()
