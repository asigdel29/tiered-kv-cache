"""Check the workload design and integrity of emitted measurements."""
import unittest

from tiered_kv_cache.benchmark import benchmark


class BenchmarkTests(unittest.TestCase):
    """Exercise warmed resident and spill paths with the same reads."""

    def test_workloads(self):
        """Require disk access for the scan and resident hits for hot pages."""
        report = benchmark(reads=32, repeats=2, page_bytes=64)
        for name, workload in report["workloads"].items():
            for trial in workload["trials"]:
                self.assertEqual(trial["resident"]["hits"]["gpu"], 32)
                self.assertEqual(sum(trial["tiered"]["hits"].values()), 32)
                self.assertEqual(len(trial["tiered"]["read_ns"]), 32)
                if name == "hot":
                    self.assertEqual(trial["tiered"]["hits"]["gpu"], 32)
                if name == "scan":
                    self.assertEqual(trial["tiered"]["hits"]["disk"], 32)
