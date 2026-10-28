"""Hash tracked and non-ignored untracked content, excluding the Triad plans tree.

Usage: worktree-fingerprint.py [EXTRA_DIR]
Always excludes $TRIAD_PLANS_DIR (default docs/plans) under the repo root; EXTRA_DIR, if
given, is excluded too (for a run folder kept elsewhere). Neither may be the repo root."""

import hashlib
import os
from pathlib import Path
import stat
import subprocess
import sys


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args])


def fingerprint(root, excluded_dirs):
    digest = hashlib.sha256()

    def add(data):
        digest.update(len(data).to_bytes(8, "big"))
        digest.update(data)

    def visit(repo):
        paths = set(git(repo, "ls-files", "-z", "--cached", "--others",
                        "--exclude-standard").split(b"\0")) - {b""}
        for raw in sorted(paths):
            path = repo / os.fsdecode(raw)
            if any(path == ex or ex in path.parents for ex in excluded_dirs):
                continue
            add(os.fsencode(path.relative_to(root)))
            try:
                info = path.lstat()
            except FileNotFoundError:
                add(b"missing")
                continue
            add(str(stat.S_IFMT(info.st_mode)).encode())
            add(str(info.st_mode & 0o111).encode())
            if path.is_symlink():
                add(os.fsencode(os.readlink(path)))
            elif path.is_file():
                add(hashlib.sha256(path.read_bytes()).digest())
            elif path.is_dir():
                # Gitlinks: record their revision and recurse into their dirty files.
                nested_root = Path(os.fsdecode(git(path, "rev-parse", "--show-toplevel")).strip())
                if nested_root.resolve() != path.resolve():
                    raise ValueError(f"cannot fingerprint uninitialized submodule: {path}")
                add(git(path, "rev-parse", "HEAD"))
                visit(path)
            else:
                raise ValueError(f"unsupported file type: {path}")

    add(git(root, "rev-parse", "HEAD"))
    visit(root)
    return digest.hexdigest()


if __name__ == "__main__":
    try:
        root = Path(os.fsdecode(git(Path.cwd(), "rev-parse", "--show-toplevel")).strip()).resolve()
        excluded = [root / os.environ.get("TRIAD_PLANS_DIR", "docs/plans")]
        excluded += [Path(arg) for arg in sys.argv[1:]]
        excluded = [path.resolve() for path in excluded]
        for path in excluded:
            if path == root or root not in path.parents:
                raise ValueError(f"excluded dir must be a subdirectory of the repository: {path}")
        print(fingerprint(root, excluded))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f"triad: fingerprint failed: {error}")
