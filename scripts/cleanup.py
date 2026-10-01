#!/usr/bin/env python3
"""cleanup.py — find and remove leftover Tempo worktrees, simulators and build caches.

Dry run by default: prints what it would remove and how much space that frees.
Pass --yes to actually remove it.

    scripts/cleanup.py            # dry run
    scripts/cleanup.py --yes      # remove

What counts as "not used any more":
  Worktree folder  no uncommitted changes, nothing running inside it, no open PR,
                   no activity for --idle-hours (default 24). Removing the folder
                   KEEPS its branch, so no commits are lost. The branch itself is
                   deleted only when all its commits are already in origin/main.
  Simulator        a shut-down Tempo simulator ("Tempo…" or "… · …") that no kept
                   worktree uses. Stock simulators ("iPhone 17") are never touched.
  Build cache      a DerivedData folder (Xcode's, /tmp, or a Claude scratchpad)
                   whose project is gone or that hasn't been built in
                   --idle-hours. The main repo's Xcode cache (used for ⌘R on the
                   iPhone) is always kept.
"""

import argparse
import json
import os
import plistlib
import shutil
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
XCODE_DD = HOME / "Library/Developer/Xcode/DerivedData"
SCRATCH_ROOTS = [Path("/private/tmp")]


def run(*cmd, cwd=None, check=False):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if check and r.returncode != 0:
        sys.exit(f"[ERR] {' '.join(cmd)}: {r.stderr.strip()}")
    return r.stdout.strip() if r.returncode == 0 else None


def git(*args, cwd):
    return run("git", *args, cwd=cwd)


def size_kb(path):
    out = run("du", "-sk", str(path))
    return int(out.split()[0]) if out else 0


def human(kb):
    gb = kb / 1024 / 1024
    return f"{gb:.1f} GB" if gb >= 1 else f"{kb / 1024:.0f} MB"


def recent(paths, cutoff):
    """True if any of the given files/dirs (or their direct children) changed after cutoff."""
    for p in paths:
        try:
            if p.stat().st_mtime > cutoff:
                return True
            if p.is_dir():
                for c in os.scandir(p):
                    if c.stat(follow_symlinks=False).st_mtime > cutoff:
                        return True
        except OSError:
            pass
    return False


def tree_recent(root, cutoff):
    """Any file in the worktree touched after cutoff (skips build output)."""
    out = run(
        "find",
        str(root),
        "(",
        "-name",
        "DerivedData",
        "-o",
        "-name",
        ".build",
        "-o",
        "-name",
        "build",
        "-o",
        "-name",
        "node_modules",
        ")",
        "-prune",
        "-o",
        "-type",
        "f",
        "-newermt",
        time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(cutoff)),
        "-print",
        "-quit",
    )
    return bool(out)


def sim_slug(root, main_root):
    """Same naming as scripts/sim.sh."""
    if root == main_root:
        return "main"
    base = root.name
    if base.startswith("tempo-"):
        base = base[len("tempo-") :]
    if base.startswith("agent-"):
        base = base[:13]
    return base


def process_cwds():
    out = run("lsof", "-a", "-d", "cwd", "-Fn") or ""
    return [Path(line[1:]) for line in out.splitlines() if line.startswith("n/")]


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument(
        "--yes", action="store_true", help="actually remove (default: dry run)"
    )
    ap.add_argument(
        "--idle-hours",
        type=float,
        default=24,
        help="untouched for this long = unused (default 24)",
    )
    args = ap.parse_args()
    cutoff = time.time() - args.idle_hours * 3600

    here = run("git", "rev-parse", "--show-toplevel", check=True)
    common = Path(
        run(
            "git", "rev-parse", "--path-format=absolute", "--git-common-dir", check=True
        )
    )
    main_root = common.parent
    this_root = Path(here)
    sim_sh = this_root / "scripts/sim.sh"

    git("fetch", "--quiet", "origin", cwd=main_root)
    prs = {}
    pr_json = run(
        "gh",
        "pr",
        "list",
        "--state",
        "all",
        "--limit",
        "500",
        "--json",
        "headRefName,state",
        cwd=main_root,
    )
    if pr_json is None:
        sys.exit(
            "[ERR] `gh pr list` failed — cannot tell which branches have open PRs. Run `gh auth status`."
        )
    for pr in json.loads(pr_json):
        prs.setdefault(pr["headRefName"], set()).add(pr["state"])
    cwds = process_cwds()

    # ---- worktrees -------------------------------------------------------
    porcelain = git("worktree", "list", "--porcelain", cwd=main_root) or ""
    worktrees = []
    cur = {}
    for line in porcelain.splitlines() + [""]:
        if not line:
            if cur:
                worktrees.append(cur)
            cur = {}
        elif line.startswith("worktree "):
            cur["path"] = Path(line[len("worktree ") :])
        elif line.startswith("branch "):
            cur["branch"] = line[len("branch refs/heads/") :]

    kept_roots, remove_wt = [main_root, this_root], []
    for wt in worktrees:
        path, branch = wt["path"], wt.get("branch")
        if path in (main_root, this_root):
            continue
        reason = None
        if not path.exists():
            continue  # stale entry; `git worktree prune` handles it
        else:
            dirty = [
                l
                for l in (git("status", "--porcelain", cwd=path) or "").splitlines()
                if not l.endswith(".xcscheme")
            ]
            if dirty:
                reason = f"{len(dirty)} uncommitted change(s)"
            elif any(c == path or path in c.parents for c in cwds):
                reason = "a process is running inside it"
            elif branch and "OPEN" in prs.get(branch, set()):
                reason = "open PR"
            elif not branch:
                head = git("rev-parse", "HEAD", cwd=path)
                if (
                    git(
                        "merge-base",
                        "--is-ancestor",
                        head,
                        "origin/main",
                        cwd=main_root,
                    )
                    is None
                ):
                    reason = "detached HEAD with commits not in main"
            elif tree_recent(path, cutoff):
                reason = f"used in the last {args.idle_hours:g}h"
        if reason:
            kept_roots.append(path)
            print(f"  keep    {path}  ({reason})")
            continue
        merged = False
        if branch:
            cherry = git("cherry", "origin/main", branch, cwd=main_root)
            merged = cherry is not None and not any(
                l.startswith("+") for l in cherry.splitlines()
            )
        remove_wt.append((path, branch, merged))

    # ---- simulators ------------------------------------------------------
    kept_sims = {f"Tempo · {sim_slug(r, main_root)}" for r in kept_roots}
    devs = json.loads(
        run("xcrun", "simctl", "list", "devices", "-j") or '{"devices": {}}'
    )["devices"]
    remove_sims = []
    for runtime_devs in devs.values():
        for d in runtime_devs:
            name = d["name"]
            ours = "tempo" in name.lower() or " · " in name
            if not ours:
                continue
            if d["state"] != "Shutdown" or name in kept_sims:
                print(
                    f'  keep    sim "{name}" ({"in use" if d["state"] != "Shutdown" else "worktree kept"})'
                )
                continue
            remove_sims.append((name, d["udid"], Path(d.get("dataPath", "")).parent))

    # ---- build caches ----------------------------------------------------
    remove_dd = []
    main_project = (main_root / "Tempo/Tempo.xcodeproj").resolve()
    if XCODE_DD.is_dir():
        for d in XCODE_DD.iterdir():
            if not d.name.startswith("Tempo-"):
                continue
            try:
                info = plistlib.loads((d / "info.plist").read_bytes())
            except (OSError, plistlib.InvalidFileException):
                info = {}
            ws = Path(info.get("WorkspacePath", "/nonexistent"))
            last = info.get("LastAccessedDate")
            last_ts = last.timestamp() if last else d.stat().st_mtime
            if ws.exists() and ws.resolve() == main_project:
                continue
            if not ws.exists() or (
                last_ts < cutoff and not recent([d / "Logs/Build"], cutoff)
            ):
                remove_dd.append(d)

    seen = set()
    candidates = [
        p for p in Path("/private/tmp").iterdir() if p.is_dir() and not p.is_symlink()
    ]
    claude_tmp = Path(f"/private/tmp/claude-{os.getuid()}")
    if claude_tmp.is_dir():
        candidates += [p for p in claude_tmp.glob("*/*/scratchpad/*") if p.is_dir()]
    keep_dds = {(r / "DerivedData").resolve() for r in kept_roots}
    for d in candidates:
        r = d.resolve()
        if r in seen or r in keep_dds:
            continue
        seen.add(r)
        if not (
            (d / "Build/Intermediates.noindex").is_dir()
            or (d / "Build/Products").is_dir()
        ):
            continue
        if recent([d / "info.plist", d / "Logs/Build", d / "Build/Products"], cutoff):
            continue
        remove_dd.append(d)

    # ---- report ----------------------------------------------------------
    total = 0
    print("\nWorktree folders to remove (branches are kept unless already in main):")
    for path, branch, merged in remove_wt:
        kb = size_kb(path)
        total += kb
        print(
            f"  {human(kb):>8}  {path}  [{branch or 'detached'}{', branch deleted: in main' if merged else ''}]"
        )
    print("\nSimulators to delete:")
    for name, udid, data in remove_sims:
        kb = size_kb(data) if data.exists() else 0
        total += kb
        print(f"  {human(kb):>8}  {name}  ({udid})")
    print("\nBuild caches to delete:")
    for d in remove_dd:
        kb = size_kb(d)
        total += kb
        print(f"  {human(kb):>8}  {d}")
    print(f"\nTotal: {human(total)}")

    if not args.yes:
        print("\nDry run — nothing removed. Re-run with --yes to remove the above.")
        return

    for path, branch, merged in remove_wt:
        if sim_sh.exists():
            run("bash", str(sim_sh), "--dir", str(path), "clean")
        if git("worktree", "remove", "--force", str(path), cwd=main_root) is None:
            print(f"  [WARN] could not remove {path}")
            continue
        if merged and branch:
            git("branch", "-D", branch, cwd=main_root)
    git("worktree", "prune", cwd=main_root)
    for name, udid, _ in remove_sims:
        run("xcrun", "simctl", "delete", udid)
    run("xcrun", "simctl", "delete", "unavailable")
    for d in remove_dd:
        shutil.rmtree(d, ignore_errors=True)
    print("\nDone.")


if __name__ == "__main__":
    main()
