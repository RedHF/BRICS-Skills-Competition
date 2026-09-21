"""Check Git candidates and optionally history against GitHub's 100 MiB limit.

Run: python tools/check_git_size.py [--staged] [--history]
This is read-only. Ignored local release bundles are excluded from candidates.
"""
from pathlib import Path
import argparse
import subprocess
import sys

LIMIT = 100 * 1024 * 1024
WARNING = 50 * 1024 * 1024


def git(*args, data=None):
    return subprocess.run(
        ["git", *args], input=data, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, check=True,
    ).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", action="store_true", help="Check index blobs only")
    parser.add_argument("--history", action="store_true", help="Also check all locally reachable commits")
    args = parser.parse_args()
    root = Path(git("rev-parse", "--show-toplevel").decode("utf-8").strip())
    entries = {}
    # Inspect actual index blobs as well as working files: the staged content may differ.
    for record in git("ls-files", "--stage", "-z").split(b"\0"):
        if not record:
            continue
        header, name = record.split(b"\t", 1)
        mode, oid, stage = header.split()
        if mode != b"160000":
            entries[oid.decode()] = "index: " + name.decode("utf-8")
    if args.history:
        for record in git("rev-list", "--objects", "--all").splitlines():
            oid, _, name = record.partition(b" ")
            entries.setdefault(oid.decode(), "history: " + name.decode("utf-8", errors="replace"))
    sizes = []
    if entries:
        data = ("\n".join(entries) + "\n").encode("ascii")
        for record in git("cat-file", "--batch-check=%(objectname) %(objecttype) %(objectsize)", data=data).splitlines():
            oid, kind, size = record.decode().split()
            if kind == "blob":
                sizes.append((int(size), entries[oid]))
    if not args.staged:
        names = set(git("ls-files", "--cached", "--others", "--exclude-standard", "-z").split(b"\0"))
        for name in names:
            if name:
                rel = name.decode("utf-8")
                path = root / rel
                if path.is_file():
                    sizes.append((path.stat().st_size, "worktree: " + rel))
    failures = [(size, name) for size, name in sizes if size >= LIMIT]
    for size, name in sorted(sizes, reverse=True):
        if size >= WARNING:
            label = "FAIL" if size >= LIMIT else "WARN"
            print(f"{label} {size / 1024**2:.2f} MiB {name}")
    print(f"{'FAIL' if failures else 'PASS'}: {len(failures)} files/blobs at or above 100 MiB.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
