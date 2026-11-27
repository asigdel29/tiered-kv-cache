"""Verify bounded placement, byte integrity, and allocation lifetime."""
from concurrent.futures import ThreadPoolExecutor
from tempfile import TemporaryDirectory
import unittest
import sqlite3

from tiered_kv_cache import CacheFull, CorruptPage, PageCache
from tiered_kv_cache.replay import replay


class CacheTests(unittest.TestCase):
    """Exercise one slot per tier to force transfers."""

    def setUp(self):
        """Create isolated scratch storage for each test."""
        directory = self.enter_tempdir()
        self.cache = PageCache(directory, page_bytes=1, gpu_pages=1, ram_pages=1, disk_pages=1)
        self.addCleanup(self.cache.close)

    def enter_tempdir(self):
        """Return a temporary directory that outlives the cache."""
        directory = TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        return directory.name

    def test_replay(self):
        self.assertEqual(replay()["hits"], {"gpu": 1, "ram": 1, "disk": 4})

    def test_bounds(self):
        handles = [self.cache.put(bytes([i])) for i in range(3)]
        with self.assertRaises(CacheFull):
            self.cache.put(b"x")
        self.cache.release(handles[0])
        replacement = self.cache.put(b"x")
        with self.assertRaises(KeyError):
            self.cache.read(handles[0])
        self.assertEqual(self.cache.read(replacement), b"x")

    def test_pin_blocks_eviction(self):
        a, b = (self.cache.put(x) for x in [b"a", b"b"])
        with self.cache.pin(b):
            with self.cache.pin(b):
                with self.assertRaises(CacheFull):
                    self.cache.prefetch(a)
            with self.assertRaises(RuntimeError):
                self.cache.release(b)
            with self.assertRaises(RuntimeError):
                self.cache.close()
        self.assertEqual(self.cache.read(a), b"a")

    def test_disk_transaction_rollback(self):
        a, b, c = (self.cache.put(x) for x in [b"a", b"b", b"c"])
        db = sqlite3.connect(self.cache._database_path)
        self.addCleanup(db.close)
        db.execute("CREATE TRIGGER fail BEFORE INSERT ON pages "
                               "BEGIN SELECT RAISE(ABORT, 'full disk'); END")
        with self.assertRaises(sqlite3.DatabaseError):
            self.cache.read(a)
        db.execute("DROP TRIGGER fail")
        self.assertEqual([self.cache.read(h) for h in [a, b, c]], [b"a", b"b", b"c"])

    def test_corrupt_page(self):
        a, _, c = (self.cache.put(x) for x in [b"a", b"b", b"c"])
        db = sqlite3.connect(self.cache._database_path)
        self.addCleanup(db.close)
        with db:
            db.execute("UPDATE pages SET data = ?", (b"x",))
        with self.assertRaises(CorruptPage):
            self.cache.read(a)
        self.assertEqual(self.cache.read(c), b"c")

    def test_concurrent_reads(self):
        values = [b"a", b"b", b"c"]
        handles = [self.cache.put(v) for v in values]
        with ThreadPoolExecutor(4) as pool:
            self.assertEqual(list(pool.map(self.cache.read, handles * 8)), values * 8)

    def test_closed(self):
        a = self.cache.put(b"a")
        self.cache.close()
        with self.assertRaises(RuntimeError):
            self.cache.read(a)

    def test_page_size(self):
        with self.assertRaises(ValueError):
            self.cache.put(b"ab")
