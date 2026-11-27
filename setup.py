"""Bundle release-mode native products inside a platform wheel."""
from pathlib import Path
import shutil
import subprocess
import sys
from setuptools import Distribution, setup
from setuptools.command.build_py import build_py


class PlatformDistribution(Distribution):
    """Mark the wheel as platform-specific."""
    def has_ext_modules(self):
        return True


class NativeBuild(build_py):
    """Build and copy the native library and executable into the package."""
    def run(self):
        subprocess.run(["zig", "build", "-Doptimize=ReleaseSafe"], check=True)
        super().run()
        dest = Path(self.build_lib) / "tiered_kv_cache" / "_bin"
        dest.mkdir(parents=True, exist_ok=True)
        library = "libtieredkv.dylib" if sys.platform == "darwin" else "libtieredkv.so"
        shutil.copy2(Path("zig-out/lib") / library, dest)
        shutil.copy2("zig-out/bin/kv-cache", dest)


setup(cmdclass={"build_py": NativeBuild}, distclass=PlatformDistribution)
