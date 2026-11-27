"""Thread-safe Python views over the native page cache."""
from contextlib import contextmanager
import ctypes as c
from dataclasses import dataclass
import os
from pathlib import Path
import sqlite3
from tempfile import TemporaryDirectory
from threading import RLock
from uuid import UUID, uuid4

from ._native import Stats, key, lib, ptr, size


class CacheFull(RuntimeError):
    """Indicate that admission needs a free slot or an unpinned victim."""


class CorruptPage(OSError):
    """Identify a missing or corrupt spill page."""


@dataclass(frozen=True)
class PageHandle:
    """Identify an allocation for the lifetime of one cache."""
    cache_id: UUID
    allocation: int


def _check(status):
    """Map native status values to the public exception types."""
    if status:
        kind, message = {
            1: (CacheFull, "all slots or GPU victims are unavailable"),
            2: (CorruptPage, "disk page failed its checksum"),
            3: (KeyError, "unknown allocation"),
            4: (RuntimeError, "page is pinned"),
            5: (sqlite3.DatabaseError, "SQLite page operation failed"),
            6: (MemoryError, "cache allocation failed"),
            7: (ValueError, "invalid cache argument"),
        }[status]
        raise kind(message)


class PageCache:
    """Serialize access to a native cache with bounded resident and disk tiers."""

    def __init__(self, directory, *, page_bytes, gpu_pages, ram_pages, disk_pages):
        """Open a private SQLite spill database and allocate native state."""
        for value in (page_bytes, gpu_pages, ram_pages, disk_pages):
            if type(value) is not int or not 0 < value <= size(-1).value:
                raise ValueError("page size and tier capacities must be positive integers")
        self._id = uuid4()
        self._lock = RLock()
        self.page_bytes = page_bytes
        self._directory = TemporaryDirectory(dir=directory)
        self._database_path = Path(self._directory.name) / "pages.db"
        self._cache = ptr()
        try:
            _check(lib.kv_open(os.fsencode(self._database_path), page_bytes, gpu_pages,
                               ram_pages, disk_pages, c.byref(self._cache)))
        except BaseException:
            self._directory.cleanup()
            raise

    def _open(self):
        """Return the live native pointer."""
        if not self._cache:
            raise RuntimeError("cache is closed")
        return self._cache

    def _id_for(self, handle):
        """Reject handles issued by a different cache."""
        self._open()
        if not isinstance(handle, PageHandle) or handle.cache_id != self._id:
            raise KeyError(handle)
        if not isinstance(handle.allocation, int) or not 0 <= handle.allocation < 2**63:
            raise KeyError(handle)
        return handle.allocation

    def put(self, payload):
        """Copy immutable bytes into a new native allocation."""
        if not isinstance(payload, bytes) or len(payload) != self.page_bytes:
            raise ValueError("expected exactly one immutable page of bytes")
        with self._lock:
            allocation = key()
            _check(lib.kv_put(self._open(), payload, len(payload), c.byref(allocation)))
            return PageHandle(self._id, allocation.value)

    def _copy(self, handle, pinned):
        """Read into an independent Python buffer while the cache lock is held."""
        allocation = self._id_for(handle)
        buf = c.create_string_buffer(self.page_bytes)
        _check(lib.kv_read(self._cache, allocation, pinned, buf))
        try:
            return buf.raw
        except BaseException:
            if pinned:
                _check(lib.kv_unpin(self._cache, allocation))
            raise

    def read(self, handle):
        """Restore a page and return its immutable bytes."""
        with self._lock:
            return self._copy(handle, False)

    def prefetch(self, handle):
        """Promote the page without copying its payload into Python."""
        with self._lock:
            _check(lib.kv_read(self._open(), self._id_for(handle), False, None))

    @contextmanager
    def pin(self, handle):
        """Prevent eviction and release until the caller leaves this context."""
        with self._lock:
            payload = self._copy(handle, True)
        try:
            yield payload
        finally:
            with self._lock:
                _check(lib.kv_unpin(self._open(), self._id_for(handle)))

    def release(self, handle):
        """Invalidate one unpinned allocation."""
        with self._lock:
            _check(lib.kv_release(self._open(), self._id_for(handle)))

    def stats(self):
        """Return placement and source hit counts from one native snapshot."""
        with self._lock:
            counts = Stats()
            lib.kv_stats(self._open(), c.byref(counts))
            tiers = ("gpu", "ram", "disk")
            return {"pages": dict(zip(tiers, counts.pages)), "hits": dict(zip(tiers, counts.hits))}

    def close(self):
        """Free native resources once all pins have been returned."""
        with self._lock:
            if self._cache:
                _check(lib.kv_close(self._cache))
                self._cache = ptr()
                self._directory.cleanup()

    def __del__(self):
        """Release abandoned instances after all pin contexts have expired."""
        if getattr(self, "_cache", None):
            self.close()

    def __enter__(self):
        self._open()
        return self

    def __exit__(self, *_):
        self.close()
