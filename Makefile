# Run the reference tests and replay on the current host.
PYTHON ?= python3
.PHONY: check demo bench
check:
	$(PYTHON) -m unittest discover -s tests -v
demo:
	$(PYTHON) -m tiered_kv_cache.replay
bench:
	$(PYTHON) -m tiered_kv_cache.benchmark $(ARGS)

.PHONY: graph
graph:
	bash scripts/graphify.sh
