# Graph Report - tiered-kv-cache  (2026-11-27)

## Corpus Check
- 13 files · ~4,036 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 183 nodes · 303 edges · 11 communities (7 shown, 4 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 1 edges (avg confidence: 0.95)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- benchmark.py
- PageCache
- cache.py
- main.zig
- storage.zig
- CacheTests
- Cache
- cache.zig
- abi.zig
- NativeBuild
- PlatformDistribution

## God Nodes (most connected - your core abstractions)
1. `PageCache` - 20 edges
2. `Cache` - 12 edges
3. `CacheTests` - 12 edges
4. `_check()` - 9 edges
5. `Store` - 8 edges
6. `run_cli()` - 8 edges
7. `status()` - 7 edges
8. `benchmark()` - 7 edges
9. `artifact()` - 7 edges
10. `benchmark()` - 7 edges

## Surprising Connections (you probably didn't know these)
- `PageCache` --uses--> `Stats`  [INFERRED]
  tiered_kv_cache/cache.py → tiered_kv_cache/_native.py
- `benchmark()` --calls--> `artifact()`  [EXTRACTED]
  tiered_kv_cache/benchmark.py → tiered_kv_cache/_native.py
- `replay()` --calls--> `artifact()`  [EXTRACTED]
  tiered_kv_cache/replay.py → tiered_kv_cache/_native.py
- `main()` --calls--> `run_cli()`  [EXTRACTED]
  tiered_kv_cache/benchmark.py → tiered_kv_cache/_native.py
- `main()` --calls--> `run_cli()`  [EXTRACTED]
  tiered_kv_cache/replay.py → tiered_kv_cache/_native.py

## Import Cycles
- None detected.

## Communities (11 total, 4 thin omitted)

### Community 0 - "benchmark.py"
Cohesion: 0.10
Nodes (7): BenchmarkTests, benchmark(), main(), artifact(), run_cli(), main(), replay()

### Community 1 - "PageCache"
Cohesion: 0.11
Nodes (3): _check(), PageCache, Stats

### Community 2 - "cache.py"
Cohesion: 0.12
Nodes (3): CacheFull, CorruptPage, PageHandle

### Community 3 - "main.zig"
Cohesion: 0.18
Nodes (18): benchmark(), close(), Counts, Delta, ensureDirectory(), f(), getenv(), main() (+10 more)

### Community 4 - "storage.zig"
Cohesion: 0.22
Nodes (11): sqlite3_bind_blob64(), sqlite3_bind_int64(), sqlite3_close(), sqlite3_column_blob(), sqlite3_column_bytes(), sqlite3_exec(), sqlite3_finalize(), sqlite3_open() (+3 more)

### Community 7 - "cache.zig"
Cohesion: 0.20
Nodes (6): Page, Stats, Tier, disk, gpu, ram

### Community 8 - "abi.zig"
Cohesion: 0.33
Nodes (7): kv_close(), kv_open(), kv_put(), kv_read(), kv_release(), kv_unpin(), status()

## Knowledge Gaps
- **10 isolated node(s):** `gpu`, `ram`, `disk`, `Page`, `Stats` (+5 more)
  These have ≤1 connection - possible missing edges. (Counts symbols only; 76 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **4 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `PageCache` connect `PageCache` to `cache.py`, `CacheTests`?**
  _High betweenness centrality (0.137) - this node is a cross-community bridge._
- **What connects `gpu`, `ram`, `disk` to the rest of the system?**
  _10 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `benchmark.py` be split into smaller, more focused modules?**
  _Cohesion score 0.0957983193277311 - nodes in this community are weakly interconnected._
- **Why does `CacheTests` connect `CacheTests` to `cache.py`?**
  _High betweenness centrality (0.061) - this node is a cross-community bridge._
- **Should `PageCache` be split into smaller, more focused modules?**
  _Cohesion score 0.10685483870967742 - nodes in this community are weakly interconnected._
- **Why does `Cache` connect `Cache` to `cache.zig`?**
  _High betweenness centrality (0.043) - this node is a cross-community bridge._
- **Should `cache.py` be split into smaller, more focused modules?**
  _Cohesion score 0.12121212121212122 - nodes in this community are weakly interconnected._