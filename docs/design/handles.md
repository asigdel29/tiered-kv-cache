# Handle ownership and pin lifetime

## Concurrency and lifetime

Python calls acquire a reentrant lock, which serializes index updates, reads, and database writes within one process. Disk latency can delay calls on unrelated pages. A pin first reads the page and increments its count under the same lock. The caller then uses the bytes outside the lock. Exiting the pin context decrements the count, including when caller code raises an exception.

A live handle identifies one allocation even when a different page has identical bytes. Release removes the page and its digest. A fresh allocation uses a new number. Close requires all pins to end and removes the temporary database. Process restart requires a new cache and new handles.

The slot limits bound payload counts. Caller references can retain returned bytes after release. The native hash map, SQLite pages, and transaction journals add storage costs.

The [native core](../../src/cache.zig) owns every placement transition. The native caller serializes access or uses a single owner. The [Python binding](../../tiered_kv_cache/cache.py) validates cache identifiers and copies read buffers before it releases its lock. Victim selection scans the index for the oldest eligible page. The [cache tests](../../tests/test_cache.py) exercise transaction rollback, corruption, concurrent reads, capacity, and pin lifetime.

## Caller contract

| Operation | Observable effect |
| --- | --- |
| `put(payload)` | Copies exactly one immutable page and returns a new handle. |
| `read(handle)` | Returns an independent Python byte string and promotes the page. |
| `prefetch(handle)` | Promotes the page synchronously and counts a read. |
| `pin(handle)` | Promotes the page and increments its pin count. Nested pins require matching exits. |
| `release(handle)` | Reclaims the slot and invalidates the handle. |
| `stats()` | Returns one snapshot of live slot counts and successful source hits. |
| `close()` | Frees native state and removes the Python cache directory after the last pin exits. |

The native read returns a borrowed slice. Its lifetime ends at eviction or release. Python copies the bytes under its lock before returning to the caller.
