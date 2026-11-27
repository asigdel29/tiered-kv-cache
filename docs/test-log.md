# Test log

## 2026-11-27 — native cache and Python API

Tested revision [19501fd](https://github.com/asigdel29/tiered-kv-cache/commit/19501fdd4652f75e14e0666e0b2cdb6178e97ca1) on macOS 27.3, arm64, with Zig 0.16.0, SQLite 3.54.0, and Python 3.15.2. The scratch directory used the local APFS data volume.

| Check | Observed result |
| --- | --- |
| `make check` | Zig formatting and native tests passed. All nine Python tests passed. |
| `zig-out/bin/kv-cache replay` | Six byte-exact reads. Source hits were one GPU, one RAM, and four disk. |
| `make demo ARGS="--rounds 100"` | 600 byte-exact reads. Source hits were one GPU, one RAM, and 598 disk. |

## Paired benchmark

```sh
zig-out/bin/kv-cache bench --seed 42 --reads 128 --repeats 7 --page-bytes 4096 --output bench-results/cache.json
```

Each row reports the tiered mean minus the resident mean, in microseconds per read. The 95% percentile interval uses 2,000 bootstrap samples over paired trial means. Hit counts come from the first measured tiered trial.

| Trace | GPU / RAM / disk hits | Mean difference (µs) | 95% interval (µs) |
| --- | --- | ---: | ---: |
| Hot | 128 / 0 / 0 | 0.006 | 0.001 to 0.013 |
| Scan | 0 / 0 / 128 | 885.734 | 374.551 to 1,493.702 |
| Mixed | 76 / 34 / 18 | 138.358 | 61.976 to 222.646 |

The payload SHA-256 was `fc0cc686ec03d788bf2cd9d5355ed951637fa09570ba7fc7ce36c423c7069a95`. These measurements cover synchronous cache calls with host buffers and a real SQLite scratch file. Filesystem caching and concurrent host activity affect the timings.

See the [measurement design](design/measurement.md) for the warmup, trace, and baseline definitions.
