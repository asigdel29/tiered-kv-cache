"""Measure logical read latency across controlled cache access patterns."""
import argparse
import hashlib
import json
import math
import os
import platform
import random
import sqlite3
import statistics
from pathlib import Path
from time import perf_counter_ns

from .cache import PageCache


def measure(trace, payloads, sizes, directory):
    """Time individual reads after one warmup pass through the same trace."""
    with PageCache(directory, page_bytes=len(payloads[0]), gpu_pages=sizes[0],
                   ram_pages=sizes[1], disk_pages=sizes[2]) as cache:
        handles = [cache.put(page) for page in payloads]
        for index in trace:
            cache.prefetch(handles[index])
        before = cache.stats()["hits"]
        samples = []
        for index in trace:
            handle = handles[index]
            start = perf_counter_ns()
            result = cache.read(handle)
            samples.append(perf_counter_ns() - start)
            if result != payloads[index]:
                raise RuntimeError(f"invalid restored payload at index {index}")
        after = cache.stats()["hits"]
    ordered = sorted(samples)
    return {
        "read_ns": samples,
        "p50_ns": statistics.median(samples),
        "p95_ns": ordered[math.ceil(0.95 * len(ordered)) - 1],
        "mean_ns": statistics.mean(samples),
        "hits": {tier: after[tier] - before[tier] for tier in after},
    }


def bootstrap(deltas, seed):
    """Estimate the interval for a mean difference by resampling paired trials."""
    rng = random.Random(seed)
    samples = sorted(statistics.mean(rng.choices(deltas, k=len(deltas))) for _ in range(2000))
    return {"mean_ns": statistics.mean(deltas), "ci95_ns": [samples[49], samples[1949]]}


def benchmark(*, reads=128, repeats=7, page_bytes=4096, seed=42, directory=None):
    """Compare two cache configurations with identical seeded bytes and traces."""
    if min(reads, page_bytes) < 1 or repeats < 2:
        raise ValueError("Use positive reads and page bytes, and at least two paired trials")
    rng = random.Random(seed)
    sizes = {"resident": (16, 1, 1), "tiered": (4, 4, 8)}
    payloads = [rng.randbytes(page_bytes) for _ in range(16)]
    workloads = {
        "hot": [15 - i % 4 for i in range(reads)],
        "scan": [i % 16 for i in range(reads)],
        "mixed": [rng.randrange(12, 16) if rng.random() < 0.8 else rng.randrange(12)
                  for _ in range(reads)],
    }
    results = {}
    for name, trace in workloads.items():
        trials = []
        deltas = []
        for index in range(repeats):
            order = list(sizes) if index % 2 == 0 else list(reversed(sizes))
            trial = {label: measure(trace, payloads, sizes[label], directory) for label in order}
            trials.append(trial)
            deltas.append(trial["tiered"]["mean_ns"] - trial["resident"]["mean_ns"])
        results[name] = {"trace": trace, "trials": trials,
                         "tiered_minus_resident": bootstrap(deltas, seed)}
    return {
        "schema_version": 1, "backend": "host-bytes/host-bytes/sqlite", "seed": seed,
        "reads": reads, "repeats": repeats, "page_bytes": page_bytes, "tier_capacities": sizes,
        "payload_sha256": hashlib.sha256(b"".join(payloads)).hexdigest(),
        "python": platform.python_version(), "platform": platform.platform(),
        "sqlite": sqlite3.sqlite_version, "revision": os.getenv("GITHUB_SHA"),
        "workloads": results,
    }


def main():
    """Save the full measurement record as JSON."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("bench-results/cache.json"))
    parser.add_argument("--reads", type=int, default=128)
    parser.add_argument("--repeats", type=int, default=7)
    parser.add_argument("--page-bytes", type=int, default=4096)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--directory", type=Path, help="parent directory for temporary databases")
    args = parser.parse_args()
    if args.reads < 1 or args.repeats < 2 or args.page_bytes < 1:
        parser.error("use positive reads and page bytes, and at least two paired trials")
    record = benchmark(reads=args.reads, repeats=args.repeats, page_bytes=args.page_bytes,
                       seed=args.seed, directory=args.directory)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record) + "\n", encoding="utf-8")
    print(f"Saved {len(record['workloads'])} workloads to {args.output}")


if __name__ == "__main__":
    main()
