# Build and verify Zig storage, commands, and Python bindings.
PYTHON ?= python3
ZIG ?= zig
.PHONY: build check demo bench graph
build:
	$(ZIG) build -Doptimize=ReleaseSafe
check: build
	$(ZIG) fmt --check build.zig src
	$(ZIG) build test
	$(PYTHON) -m unittest discover -s tests -v
demo: build
	zig-out/bin/kv-cache replay $(ARGS)
bench: build
	zig-out/bin/kv-cache bench $(ARGS)
graph:
	bash scripts/graphify.sh
