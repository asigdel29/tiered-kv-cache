# Tiered KV cache

This library stores fixed-size, immutable KV pages in three bounded tiers. Use it to test admission, eviction, and page recovery.

## Documentation

- [System design and UML diagrams](docs/system-design.md)
- [Operations, benchmark fields, and troubleshooting](docs/operations.md)
- [Repository instructions](AGENTS.md)

## Quickstart

Use Python 3.10 or later. The reference implementation uses the Python standard library.

1. Run `make check` to test the cache.
2. Run `make demo` to replay three pages.
3. Run `make bench` to write the benchmark report.

The demo reports one GPU hit, one RAM hit, and four disk hits. It checks each returned byte.

## Architecture

```text
GPU tier (host bytes)  <-->  RAM tier (host bytes)  <-->  SQLite file
       pin / read             LRU demotion                 checksum on restore
```

The GPU and RAM tiers simulate device and host storage with Python bytes. The disk tier uses a private SQLite database.
Select an NVMe mount with `python3 -m tiered_kv_cache.replay --directory /path/to/mount`.
The operating system can cache disk reads. Physical GPU transfer, pinned host allocation, and asynchronous device operations remain future work.

## Use the API

```python
from tiered_kv_cache import PageCache

with PageCache(None, page_bytes=4, gpu_pages=1, ram_pages=1, disk_pages=1) as cache:
    handle = cache.put(b"keys")
    cache.prefetch(handle)
    with cache.pin(handle) as payload:
        assert payload == b"keys"
    cache.release(handle)
```

Pass an existing scratch directory or use `None` for the system temporary directory. Each cache owns its database until close.
Successful reads promote the page to the GPU tier. A pin prevents eviction and release.
Admission raises `CacheFull` when all GPU pages have pins or all slots hold allocated pages.
Release the page when its request ends. Old handles cannot access new allocations.

The limits count payload slots. SQLite metadata, transaction journals, temporary copies, and caller-owned bytes use extra space.
A lock serializes cache operations. A failed disk transaction preserves the previous page layout.
Use `stats()` to inspect occupancy and source-tier hits. The replay measures logical transfers.

## Benchmarks and CI

Run `make bench` to write `bench-results/cache.json`. Use the same seed, Python version, SQLite version, and storage device for repeat comparisons.

```sh
make bench ARGS="--seed 42 --reads 256 --repeats 10 --page-bytes 4096 --output bench-results/cache.json"
```

The resident baseline holds all 16 pages in the first tier. The tiered configuration uses four GPU slots, four RAM slots, and eight disk slots.

| Workload | Page access pattern |
| --- | --- |
| Hot | Cycle through the four most recent pages. |
| Scan | Visit all 16 pages in allocation order. |
| Mixed | Choose a hot page with probability 0.8. Choose other pages for the remaining accesses. |

Each trial warms a new cache with one trace pass. The measured pass times each read and verifies every byte after the timer stops.
The report records raw latencies, hit counts, the trace, the payload digest, and host details.
The comparison reports tiered minus resident mean read latency. Its 95% percentile bootstrap interval uses 2,000 resamples of paired trial means.
Trials alternate execution order. These measurements include Python, SQLite, and operating system cache costs.

CI builds and installs the wheel on three Python versions. Tests run outside the checkout.
The benchmark job uploads the JSON report to the workflow run for 30 days. Hosted runner load can affect timings.

## License

The source and tests use the Apache License 2.0.

## Graphify source map

Read the [source map report](graphify-out/GRAPH_REPORT.md) or query the [graph data](graphify-out/graph.json). Open the [interactive map](graphify-out/graph.html) locally in a browser.

Install Graphify 0.9.76 with `uv tool install graphifyy==0.9.76`. Run these commands from the repository root.

```sh
make graph
graphify query "PageCache"
```

The build reads tracked Python files from the working tree, including tests. Stage new Python files before you refresh the map. Graphify uses local syntax analysis with model backends disabled. The system design diagrams describe runtime behavior.
