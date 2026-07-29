"""Shared path policy for the launch-critical guard.

THE LAYOUT (canonical, 2026-07-29)

    ~/code/<project>/          container only — never a checkout
    ~/code/<project>/main/     the clean main checkout; agents NEVER write here
    ~/code/<project>/wt-<slug>/  every agent's working tree

One rule expresses both this layout and the one it replaces: deny anything
inside ~/code/<project>, EXCEPT inside a wt-* directory. Today the checkout is
at ~/code/<project> itself and worktrees live elsewhere; after migration the
checkout is ~/code/<project>/main and worktrees are siblings. The rule is
correct in both, so enforcement does not have to be sequenced with the move.
"""

import os

# The container directories. The checkout may be the container itself (current)
# or <container>/main (target); both are denied, and wt-* is carved out below.
LAUNCH_CRITICAL = {
    "fram": (
        "fram is the running database engine. `north up` REFUSES to launch on a"
        " tracked-dirty checkout, so writing here can leave the daemon"
        " unrestartable and block every rebuild from being adopted."
    ),
    "north": (
        "north is launch-critical and `firn rebuild` builds a COMMIT SNAPSHOT, so"
        " uncommitted work here is silently absent from the generation."
    ),
    "beagle": (
        "beagle compiles north and nixos-config; a half-edited checkout breaks"
        " builds for every other lane at once."
    ),
    "nixos-config": (
        "nixos-config is the system source and `firn rebuild` snapshots commits,"
        " so uncommitted work here never reaches a generation."
    ),
}

CODE_ROOT = os.path.expanduser("~/code")


def _within(path, root):
    """Is PATH the directory ROOT or something beneath it?"""
    return path == root or path.startswith(root + os.sep)


def protected_project(path):
    """(project, reason) when PATH is inside a protected checkout, else None.

    A wt-* directory anywhere beneath the container is the sanctioned place to
    work and is never protected — that carve-out is what makes this rule hold
    across the layout migration.
    """
    if not isinstance(path, str) or not path:
        return None
    try:
        real = os.path.realpath(path)
    except Exception:
        return None

    for project, why in LAUNCH_CRITICAL.items():
        container = os.path.realpath(os.path.join(CODE_ROOT, project))
        if not _within(real, container):
            continue

        rest = real[len(container):].lstrip(os.sep)
        first = rest.split(os.sep)[0] if rest else ""

        # Worktrees are the sanctioned destination, always.
        if first.startswith("wt-"):
            return None

        # After migration the CHECKOUT is <container>/main and the container
        # itself holds only main/ and wt-*/ — writing a symlink or scratch file
        # at the container root cannot dirty any checkout, so protecting it is
        # over-broad and produces denials with no compliant alternative.
        # Before migration the container IS the checkout and everything under
        # it must be protected. Distinguish by where .git actually lives.
        if os.path.isdir(os.path.join(container, "main", ".git")):
            if first != "main":
                return None

        return (project, why)
    return None


def worktree_advice(project):
    """The exact commands to work correctly, in the canonical layout."""
    container = os.path.join(CODE_ROOT, project)
    return (
        "Work in a worktree, then land through a ref:\n"
        f"  git -C {container}/main worktree add {container}/wt-<slug> -b <slug>\n"
        f"  # edit + commit in {container}/wt-<slug>, then land it:\n"
        f"  git -C {container}/main merge --ff-only <slug>\n"
        f"  # (plain `fetch <wt> <b>:refs/heads/main` cannot be used: main is checked out)\n"
    )
