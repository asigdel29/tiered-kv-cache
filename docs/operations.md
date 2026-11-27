# Operate and measure the page cache

## Run a placement check

Build the native executable with Zig 0.16.0 from the repository root. Run the replay on the storage volume that will hold the scratch database.

```sh
mkdir -p /tmp/kv-cache-replay
zig-out/bin/kv-cache replay --directory /tmp/kv-cache-replay --rounds 1
```

The replay allocates three 4,096-byte pages. Each tier holds one page. The trace reads pages in order 2, 1, 0, 2, 1, 0. Check the JSON for six verified reads. Source hit counts should equal one GPU, one RAM, and four disk accesses. The cache removes its private directory on close.

## Size and use a cache

1. Set the page size to the byte count of one serialized KV page.
2. Assign positive integer slot counts to all three tiers.
3. Allocate one handle for each live page.
4. Use a pin context when a consumer needs the GPU slot throughout an operation.
5. Release handles when their request finishes.
6. Close the cache after all pin contexts exit.

A call to `prefetch` completes the read synchronously. Both prefetch and pin acquisition contribute to hit counts. Take snapshots before and after the interval of interest. Subtract their hit counts to obtain accesses by source tier.

## Interpret a benchmark

```sh
make bench ARGS="--reads 128 --repeats 7 --seed 42 --page-bytes 4096 --output bench-results/cache.json"
```

Each configuration reads the same seeded payloads and trace. A resident trial allocates 16 GPU slots. A tiered trial allocates four GPU, four RAM, and eight disk slots. Each trial runs one warmup pass before measurement.

| Report field | Interpretation |
| --- | --- |
| `workloads.scan.trace` | Logical page indices in request order. |
| `workloads.scan.trials[0].tiered.hits` | Source hit counts for the measured pass. Their sum equals the number of reads. |
| `workloads.scan.trials[0].tiered.read_ns` | Individual call durations in nanoseconds. These include native page lookup, promotion, and SQLite operations. Python binding overhead is outside the measured interval. |
| `workloads.scan.tiered_minus_resident.mean_ns` | Mean paired latency difference. A positive value indicates extra time per tiered read. |
| `workloads.scan.tiered_minus_resident.ci95_ns` | Percentile bootstrap interval based on 2,000 resamples of paired trial means. |

Compare runs with the same trace, payload digest, runtime, and filesystem. Record the device that backs the scratch directory. The operating system can serve SQLite reads from its file cache.

## Diagnose an error

| Signal | Explanation | Action |
| --- | --- | --- |
| `CacheFull` during allocation | The total slot budget is full or every GPU slot has a pin. | Release an unused allocation or end a pin before retry. |
| `CacheFull` during promotion | Every GPU victim has a pin. | Retry after a pin context exits. |
| `KeyError` | The handle belongs to another cache or a released allocation. | Resolve the live handle from its owner. |
| `CorruptPage` | A disk row is missing or differs from its recorded digest. | Rebuild the affected payload from the caller's source. |
| SQLite write error | SQLite could not commit the placement change. | Inspect free space and write permissions for the scratch volume. |
| `RuntimeError` during release or close | A live pin prevents the operation. | End the pin context before cleanup. |

See the [system design](system-design.md) for cache invariants and transaction order.
