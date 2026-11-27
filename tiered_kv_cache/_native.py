"""Load the compiled Zig library or executable from this installation."""
import ctypes as c
import os
from pathlib import Path
import sys

_PACKAGE = Path(__file__).resolve().parent
_LIB = "libtieredkv.dylib" if sys.platform == "darwin" else "libtieredkv.so"


def artifact(name, kind):
    """Find a packaged artifact or the product of a local Zig build."""
    for path in (_PACKAGE / "_bin" / name, _PACKAGE.parent / "zig-out" / kind / name):
        if path.is_file():
            return path
    raise ImportError(f"Missing {name}. Install the platform wheel or run zig build.")


def run_cli(command, argv):
    """Replace the compatibility command with the native executable."""
    binary = artifact("kv-cache", "bin")
    os.execv(binary, [str(binary), command, *argv])


class Stats(c.Structure):
    """Counts returned by the native snapshot operation."""
    _fields_ = [("pages", c.c_uint64 * 3), ("hits", c.c_uint64 * 3)]


lib = c.CDLL(str(artifact(_LIB, "lib")))
ptr = c.c_void_p
size = c.c_size_t
key = c.c_int64
lib.kv_open.argtypes = [c.c_char_p, size, size, size, size, c.POINTER(ptr)]
lib.kv_close.argtypes = [ptr]
lib.kv_put.argtypes = [ptr, c.c_char_p, size, c.POINTER(key)]
lib.kv_read.argtypes = [ptr, key, c.c_bool, ptr]
lib.kv_release.argtypes = [ptr, key]
lib.kv_unpin.argtypes = [ptr, key]
lib.kv_stats.argtypes = [ptr, c.POINTER(Stats)]
lib.kv_stats.restype = None
