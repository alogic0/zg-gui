#!/usr/bin/env python3
"""Explicitly import an immutable engine commit; builds never run this updater."""
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile


def git(source, *args):
    return subprocess.check_output(["git", "-C", str(source), *args])


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: python3 tools/update_diagram_engine.py SOURCE_CHECKOUT EXACT_COMMIT")
    source = Path(sys.argv[1]).resolve()
    revision = git(source, "rev-parse", "--verify", sys.argv[2] + "^{commit}").decode().strip()
    if sys.argv[2] != revision:
        raise SystemExit("pass the full reviewed commit ID, not a moving ref or abbreviation")
    vendor = Path(__file__).resolve().parent.parent / "vendor"
    target = vendor / "diagram_engine"
    lock = vendor / "diagram_engine.lock.json"
    with tempfile.TemporaryDirectory(prefix=".diagram-import-", dir=vendor) as temp:
        staging = Path(temp) / "source"
        staging.mkdir()
        files = {}
        with tarfile.open(fileobj=io.BytesIO(git(source, "archive", "--format=tar", revision))) as archive:
            for member in archive:
                path = PurePosixPath(member.name)
                allowed = member.name in {"build.zig", "build.zig.zon", "build.sh", "README.md", "CHANGELOG.md", "LICENSE"} or path.parts[0] in {"src", "tools"}
                if not allowed or member.isdir():
                    continue
                if not member.isfile() or path.is_absolute() or ".." in path.parts:
                    raise SystemExit("unsupported archive member: " + member.name)
                data = archive.extractfile(member).read()
                output = staging / member.name
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_bytes(data)
                if member.mode & 0o111:
                    output.chmod(0o755)
                files[member.name] = hashlib.sha256(data).hexdigest()
        version = re.search(r'\.version\s*=\s*"([^"]+)"', (staging / "build.zig.zon").read_text()).group(1)
        manifest = {"schema": 1, "source": "zig-mermaid-viewer", "revision": revision, "version": version, "license": "LICENSE", "files": dict(sorted(files.items()))}
        lock_bytes = (json.dumps(manifest, indent=2) + "\n").encode()
        staged_lock = Path(temp) / "lock.json"
        staged_lock.write_bytes(lock_bytes)
        previous = Path(temp) / "previous"
        if target.exists():
            target.rename(previous)
        try:
            staging.rename(target)
            staged_lock.replace(lock)
        except BaseException:
            if target.exists():
                shutil.rmtree(target)
            if previous.exists():
                previous.rename(target)
            raise
    print(f"Pinned {len(files)} files from {revision} (version {version})")


if __name__ == "__main__":
    main()
