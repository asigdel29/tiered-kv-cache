# Graph Report - tiered-kv-cache  (2026-11-26)

## Corpus Check
- 6 files · ~1,554 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 97 nodes · 153 edges · 7 communities (2 shown, 5 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- PageCache
- cache.py
- benchmark.py
- CacheTests
- replay.py
- CacheFull
- test_benchmark.py

## God Nodes (most connected - your core abstractions)
1. `PageCache` - 22 edges
2. `CacheTests` - 12 edges
3. `benchmark()` - 11 edges
4. `CacheFull` - 7 edges
5. `measure()` - 6 edges
6. `CorruptPage` - 6 edges
7. `replay()` - 6 edges
8. `bootstrap()` - 5 edges
9. `main()` - 5 edges
10. `main()` - 5 edges

## Surprising Connections (you probably didn't know these)
- `measure()` --calls--> `PageCache`  [EXTRACTED]
  tiered_kv_cache/benchmark.py → tiered_kv_cache/cache.py
- `replay()` --calls--> `PageCache`  [EXTRACTED]
  tiered_kv_cache/replay.py → tiered_kv_cache/cache.py

## Import Cycles
- None detected.

## Communities (7 total, 5 thin omitted)

### Community 2 - "benchmark.py"
Cohesion: 0.23
Nodes (3): benchmark(), bootstrap(), measure()

### Community 4 - "replay.py"
Cohesion: 0.25
Nodes (3): main(), main(), replay()

## Knowledge Gaps
- **5 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `PageCache` connect `PageCache` to `cache.py`, `benchmark.py`, `CacheTests`, `replay.py`, `CacheFull`?**
  _High betweenness centrality (0.537) - this node is a cross-community bridge._
- **Should `PageCache` be split into smaller, more focused modules?**
  _Cohesion score 0.11231884057971014 - nodes in this community are weakly interconnected._
- **Why does `CacheTests` connect `CacheTests` to `cache.py`, `replay.py`?**
  _High betweenness centrality (0.173) - this node is a cross-community bridge._
- **Should `cache.py` be split into smaller, more focused modules?**
  _Cohesion score 0.12631578947368421 - nodes in this community are weakly interconnected._
- **Why does `benchmark()` connect `benchmark.py` to `replay.py`, `test_benchmark.py`?**
  _High betweenness centrality (0.070) - this node is a cross-community bridge._