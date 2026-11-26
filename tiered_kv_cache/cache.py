"""Manage immutable KV pages across two resident tiers and a disk tier."""
from collections import Counter, OrderedDict
from contextlib import contextmanager
from dataclasses import dataclass
import hashlib
from pathlib import Path
import sqlite3
from tempfile import TemporaryDirectory
from threading import RLock
from uuid import UUID, uuid4


class CacheFull(RuntimeError):
    """Indicate that admission requires a free page or an unpinned victim."""


class CorruptPage(OSError):
    """Indicate a missing or damaged disk page."""


@dataclass(frozen=True)
class PageHandle:
    """Identify an allocation for the lifetime of one cache."""
    cache_id: UUID
    allocation: int


class PageCache:
    """Provide synchronous, thread-safe access to fixed-size pages."""

    def __init__(self, directory, *, page_bytes, gpu_pages, ram_pages, disk_pages):
        """Set page limits and create a private temporary spill directory."""
        for value in (page_bytes, gpu_pages, ram_pages, disk_pages):
            if type(value) is not int or value < 1:
                raise ValueError("page size and tier capacities must be positive integers")
        self.page_bytes = page_bytes
        self._gpu_limit = gpu_pages
        self._ram_limit = ram_pages
        self._limit = gpu_pages + ram_pages + disk_pages
        self._id = uuid4()
        self._next = 0
        self._gpu = OrderedDict()
        self._ram = OrderedDict()
        self._digests = {}
        self._pins = Counter()
        self._hits = Counter()
        self._lock = RLock()
        self._directory = TemporaryDirectory(dir=directory)
        self._db = sqlite3.connect(Path(self._directory.name) / "pages.db",
                                   check_same_thread=False)
        self._db.execute("CREATE TABLE pages (id INTEGER PRIMARY KEY, data BLOB NOT NULL)")
        self._closed = False

    def _require_open(self):
        """Reject operations after cleanup."""
        if self._closed:
            raise RuntimeError("cache is closed")

    def _locate(self, handle):
        """Check ownership and return the source tier."""
        self._require_open()
        if handle.cache_id != self._id or handle.allocation not in self._digests:
            raise KeyError(handle)
        if handle.allocation in self._gpu:
            return "gpu"
        if handle.allocation in self._ram:
            return "ram"
        return "disk"

    def _admit(self, key, payload, source):
        """Plan evictions and commit disk changes before updating resident tiers."""
        gpu_victim = None
        ram_victim = None
        if len(self._gpu) == self._gpu_limit:
            gpu_victim = next((k for k in self._gpu if not self._pins[k]), None)
            if gpu_victim is None:
                raise CacheFull("all GPU pages are pinned")
            if len(self._ram) == self._ram_limit and source != "ram":
                ram_victim = next(iter(self._ram))
        with self._db:
            if source == "disk":
                self._db.execute("DELETE FROM pages WHERE id = ?", (key,))
            if ram_victim is not None:
                self._db.execute("INSERT INTO pages VALUES (?, ?)",
                                 (ram_victim, self._ram[ram_victim]))
        if source == "ram":
            del self._ram[key]
        if ram_victim is not None:
            del self._ram[ram_victim]
        if gpu_victim is not None:
            self._ram[gpu_victim] = self._gpu.pop(gpu_victim)
        self._gpu[key] = payload

    def put(self, payload):
        """Allocate a fresh page in the GPU tier."""
        if not isinstance(payload, bytes) or len(payload) != self.page_bytes:
            raise ValueError("expected exactly one immutable page of bytes")
        with self._lock:
            self._require_open()
            if len(self._digests) == self._limit:
                raise CacheFull("all page slots are allocated")
            key = self._next
            self._admit(key, payload, None)
            self._digests[key] = hashlib.sha256(payload).digest()
            self._next += 1
            return PageHandle(self._id, key)

    def read(self, handle):
        """Restore a page to the GPU tier and return its bytes."""
        with self._lock:
            source = self._locate(handle)
            key = handle.allocation
            if source == "gpu":
                self._gpu.move_to_end(key)
            else:
                if source == "ram":
                    payload = self._ram[key]
                else:
                    row = self._db.execute("SELECT data FROM pages WHERE id = ?", (key,)).fetchone()
                    if row is None or hashlib.sha256(row[0]).digest() != self._digests[key]:
                        raise CorruptPage(f"disk page {key} failed its checksum")
                    payload = row[0]
                self._admit(key, payload, source)
            self._hits[source] += 1
            return self._gpu[key]

    def prefetch(self, handle):
        """Promote a page before its next use."""
        self.read(handle)

    @contextmanager
    def pin(self, handle):
        """Keep a page in the GPU tier until the caller exits the context."""
        with self._lock:
            payload = self.read(handle)
            self._pins[handle.allocation] += 1
        try:
            yield payload
        finally:
            with self._lock:
                self._pins[handle.allocation] -= 1
                if not self._pins[handle.allocation]:
                    del self._pins[handle.allocation]

    def release(self, handle):
        """Free an unpinned page and invalidate its handle."""
        with self._lock:
            source = self._locate(handle)
            key = handle.allocation
            if self._pins[key]:
                raise RuntimeError("page is pinned")
            if source == "disk":
                with self._db:
                    self._db.execute("DELETE FROM pages WHERE id = ?", (key,))
            elif source == "ram":
                del self._ram[key]
            else:
                del self._gpu[key]
            del self._digests[key]

    def stats(self):
        """Return current page counts and successful accesses by source tier."""
        with self._lock:
            self._require_open()
            return {"pages": {"gpu": len(self._gpu), "ram": len(self._ram),
                              "disk": len(self._digests) - len(self._gpu) - len(self._ram)},
                    "hits": {t: self._hits[t] for t in ("gpu", "ram", "disk")}}

    def close(self):
        """Remove all pages after callers release their pins."""
        with self._lock:
            if self._pins:
                raise RuntimeError("cache has pinned pages")
            if not self._closed:
                self._db.close()
                self._directory.cleanup()
                self._gpu.clear()
                self._ram.clear()
                self._digests.clear()
                self._closed = True

    def __enter__(self):
        """Return the open cache."""
        self._require_open()
        return self

    def __exit__(self, *_):
        """Release cache storage."""
        self.close()
