# Measurement design

The CLI generates 16 immutable payloads and three access traces from the selected seed.

| Workload | Page access pattern |
| --- | --- |
| Hot | Cycle through the four most recently allocated pages. |
| Scan | Visit indices 0 through 15 in order. |
| Mixed | Choose a hot page with probability 0.8. Choose one of the other 12 pages for the remaining accesses. |

Each configuration reads the same seeded payloads and trace. A resident trial allocates 16 GPU slots. A tiered trial allocates four GPU, four RAM, and eight disk slots. Each trial runs one warmup pass before measurement.

| Report field | Interpretation |
| --- | --- |
| `workloads.scan.trace` | Logical page indices in request order. |
| `workloads.scan.trials[0].tiered.hits` | Source hit counts for the measured pass. Their sum equals the number of reads. |
| `workloads.scan.trials[0].tiered.read_ns` | Individual call durations in nanoseconds. These include native page lookup, promotion, and SQLite operations. Python binding overhead is outside the measured interval. |
| `workloads.scan.tiered_minus_resident.mean_ns` | Mean paired latency difference. A positive value indicates extra time per tiered read. |
| `workloads.scan.tiered_minus_resident.ci95_ns` | Percentile bootstrap interval based on 2,000 resamples of paired trial means. |

Compare runs with the same trace, payload digest, runtime, and filesystem. Record the device that backs the scratch directory. The operating system can serve SQLite reads from its file cache.

The first trial measures the resident layout first. Successive trials alternate the order. The bootstrap draws 2,000 samples from the paired trial differences. Each difference is one tiered trial mean minus its resident trial mean.

The report records its seed, runtime versions, payload digest, complete trace, and individual latencies. Compare trace arrays and digests before comparing releases. The native generator defines its own seeded sequence.

See the [benchmark implementation](../../src/main.zig) and the [test log](../test-log.md).
