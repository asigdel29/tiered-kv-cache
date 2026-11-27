# Repository instructions

This repository implements a synchronous, fixed-size page cache in Python. Start with the [system design](docs/system-design.md) and the [operating guide](docs/operations.md).

- Keep the public types and exceptions in `tiered_kv_cache/__init__.py` compatible with existing callers.
- Keep handle validation, pin counts, tier placement, and hit accounting under the cache lock.
- Complete the disk transaction before changing resident placement.
- Run `make check` after an implementation change.
- Run `make demo` after a change to admission, promotion, or cleanup.
- Run `make bench` after a change to the access path or measurement method.
- Report the seed, payload size, trace, runtime versions, filesystem, and paired interval with performance results.
- Describe the first two tiers as host-byte simulations. Identify SQLite as the disk backend.
- Update the design diagrams when ownership, transaction order, or tier behavior changes.

Use short, active sentences in documentation. Give each public interface a purpose statement.

Use `graphify query "PageCache"` to locate related code. Run `make graph` after source structure changes.
