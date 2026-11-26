"""Exercise deterministic page transfers with byte-exact checks."""
import argparse
import json
from .cache import PageCache


def replay(directory=None, rounds=1):
    """Replay three fixed pages and report verified reads by source."""
    if rounds < 1:
        raise ValueError("rounds must be positive")
    payloads = [bytes([v]) * 4096 for v in range(3)]
    with PageCache(directory, page_bytes=4096, gpu_pages=1, ram_pages=1, disk_pages=1) as cache:
        handles = [cache.put(payload) for payload in payloads]
        for _ in range(rounds):
            for index in (2, 1, 0, 2, 1, 0):
                if cache.read(handles[index]) != payloads[index]:
                    raise RuntimeError(f"payload mismatch for page {index}")
        return {"backend": "host-bytes/host-bytes/sqlite", "verified_reads": rounds * 6,
                **cache.stats()}


def main():
    """Run the replay in the selected scratch directory."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", help="existing parent directory for temporary disk pages")
    parser.add_argument("--rounds", type=int, default=1)
    args = parser.parse_args()
    print(json.dumps(replay(args.directory, args.rounds), sort_keys=True))


if __name__ == "__main__":
    main()
