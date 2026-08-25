"""Shared path policy for the main-checkout guard.

THE LAYOUT — directory = lifecycle policy

    ~/code/<project>/               container only — never a checkout
    ~/code/<project>/main/          the clean checkout: read-only product, and
                                    any dirt in it is the human's
    ~/code/<project>/worktrees/<slug>/  ephemeral agent lanes — sweepable, and
                                    the sanctioned destination for every write
    ~/code/<project>/pins/<full-object-id>/ externally CONSUMED checkouts — the full
                                    commit object ID is the directory name;
                                    contents and HEAD are immutable
                                    outside this repository reads them at that
                                    exact path and revision, so automation
                                    never writes to them and never sweeps them
    ~/code/<project>/pins/<full-object-id>.pin  one-line manifest naming that pin's
                                    consumers

The slot directly under the container carries the lifecycle policy. Lane leaf
names carry none; a pin leaf additionally carries the checkout's full object
identity. `worktrees` and `pins` are matched POSITIONALLY at container depth,
never anywhere in the path — `main/docs/worktrees/x.md` is repository content,
not a lane.

EVERY `main` checkout under ~/code is protected, not only the launch-critical
ones: `main` is never edited in place anywhere, and dirty state there is the
human's. Detection is dynamic — an ancestor directory named `main` holding a
`.git` — so a project is covered the day it is cloned. Client repos nest
(~/code/client/<owner>/<project>/main) and fall out of the same rule.
"""

import os
import re

# Containers whose PRIMARY breaks something beyond itself. They are protected by
# the same rule as every other main; only the reason text is theirs.
LAUNCH_CRITICAL = {
    "north": (
        "north is launch-critical and `firn rebuild` builds a COMMIT SNAPSHOT, so"
        " uncommitted work here is silently absent from the generation."
    ),
    "beagle": (
        "beagle is launch-critical: it compiles north and nixos-config, and a"
        " half-edited checkout breaks builds for every other lane at once."
    ),
    "nixos-config": (
        "nixos-config is launch-critical: it is the system source and `firn"
        " rebuild` snapshots commits, so uncommitted work here never reaches a"
        " generation."
    ),
}

GENERIC_REASON = (
    "`main` is the clean checkout of a project — nothing is edited there, by"
    " anyone, and uncommitted state in it belongs to the human."
)

# The two policy-bearing slots directly under a container.
WORKTREES_DIR = "worktrees"
PINS_DIR = "pins"

# Kinds returned alongside the container, so a caller can render the right noun
# and the right remedy. A pin hit carries its name: the remedy is the manifest.
MAIN_KIND = "main"
PIN_KIND = "pin:"

# Read-only context by policy; never a work destination, so never protected here.
EXCLUDED_ROOTS = ("resources",)


def code_root():
    """The ~/code root. Overridable so tests can build a fixture layout."""
    return os.path.realpath(
        os.environ.get("LAUNCH_CRITICAL_CODE_ROOT") or os.path.expanduser("~/code"))


def _within(path, root):
    """Is PATH the directory ROOT or something beneath it?"""
    return path == root or path.startswith(root + os.sep)


def _reason(container):
    return LAUNCH_CRITICAL.get(container, GENERIC_REASON)


def _container_slot(root, parts):
    """(container, index of the slot component) for the shallowest container.

    A container is a directory holding `main/.git`; the SLOT is the component
    directly beneath it — `main`, `worktrees`, `pins`, or anything else the
    human parked there. Anchoring at container depth is what keeps a nested
    checkout deeper in the tree from being read as this container's primary.
    """
    for i in range(1, len(parts)):
        if os.path.exists(os.path.join(root, *(parts[:i] + ["main", ".git"]))):
            return (os.sep.join(parts[:i]), i)
    return (None, None)


def _pin_manifest(root, container, name):
    """The `pins/<object-id>.pin` consumer manifest, or None."""
    try:
        with open(os.path.join(root, container, PINS_DIR, name + ".pin"),
                  encoding="utf-8", errors="replace") as handle:
            return " ".join(handle.read(4096).split()) or None
    except Exception:
        return None


def _pin_reason(root, container, name):
    manifest = _pin_manifest(root, container, name)
    listed = (f"Consumers, from {container}/{PINS_DIR}/{name}.pin: {manifest}"
              if manifest else
              f"No {container}/{PINS_DIR}/{name}.pin manifest exists — a pin whose"
              " consumers cannot be named is one the human has to rule on, not one"
              " an agent may edit.")
    return (
        f"{container}/{PINS_DIR}/{name} is an externally CONSUMED checkout."
        " It is protected because something outside this repository reads it at"
        " exactly this path and revision — not because the dirt would be the"
        f" human's. {listed}")


def protected_project(path):
    """(container, reason, kind) when PATH is inside a protected checkout.

    CONTAINER is relative to the code root, so a nested client container
    ("client/<owner>/<project>") names itself correctly in the advice. KIND is
    `main` for the clean checkout, `pin:<name>` for an externally consumed one.
    None means the path is not protected.
    """
    if not isinstance(path, str) or not path:
        return None
    try:
        real = os.path.realpath(path)
    except Exception:
        return None

    root = code_root()
    if not _within(real, root):
        return None

    rest = real[len(root):].strip(os.sep)
    parts = [p for p in rest.split(os.sep) if p] if rest else []
    if not parts or parts[0] in EXCLUDED_ROOTS:
        return None

    container, slot_index = _container_slot(root, parts)
    slot = parts[slot_index] if slot_index is not None else None

    # A pin, before anything about `main`: its protection has a different WHY
    # and a different remedy. The `pins/` directory ITSELF stays writable — a
    # container has to be able to grow one — and so is the `<name>.pin`
    # MANIFEST: it is pin metadata agents administer, not consumed checkout
    # content. Only the checkout under `pins/<object-id>/` is protected. The
    # layout checker separately rejects leaves that are not full commit IDs.
    if slot == PINS_DIR and len(parts) > slot_index + 1:
        leaf = parts[slot_index + 1]
        if leaf.endswith(".pin") and len(parts) == slot_index + 2:
            return None
        name = leaf[:-4] if leaf.endswith(".pin") else leaf
        return (container, _pin_reason(root, container, name), PIN_KIND + name)

    # Lanes are the sanctioned destination, always. Positional, never a
    # substring match: `<container>/main/docs/worktrees/` is repository content.
    if slot == WORKTREES_DIR:
        return None

    # The nearest ancestor named `main` that is actually a checkout. A `main`
    # directly under the code root has no container and is not this layout. The
    # scan STOPS at a `worktrees` or `pins` component: below one, a `main` is a
    # lane whose slug is literally `main`, or a checkout inside a pin — never
    # this container's primary.
    for i, part in enumerate(parts):
        if i > 0 and part in (WORKTREES_DIR, PINS_DIR):
            break
        if part != "main" or i == 0:
            continue
        if os.path.exists(os.path.join(root, *(parts[:i + 1] + [".git"]))):
            found = os.sep.join(parts[:i])
            return (found, _reason(found), MAIN_KIND)
    return None


def pin_sidecar(path):
    """(container, object-id, pin-path) for one live top-level pin sidecar.

    Sidecars stay writable metadata. Deleting one while its pin still exists is
    different: that would erase the only consumer record without retiring the
    checkout, so raw deletion is refused in favor of `pin-retire`.
    """
    if not isinstance(path, str) or not path:
        return None
    try:
        real = os.path.realpath(path)
    except Exception:
        return None
    root = code_root()
    if not _within(real, root):
        return None
    rest = real[len(root):].strip(os.sep)
    parts = [p for p in rest.split(os.sep) if p] if rest else []
    if not parts or parts[0] in EXCLUDED_ROOTS:
        return None
    container, slot_index = _container_slot(root, parts)
    if (container is None or slot_index is None
            or len(parts) != slot_index + 2
            or parts[slot_index] != PINS_DIR):
        return None
    leaf = parts[slot_index + 1]
    match = re.fullmatch(r"([0-9a-f]{40})\.pin", leaf)
    if not match:
        return None
    name = match.group(1)
    pin_path = os.path.join(root, container, PINS_DIR, name)
    return (container, name, pin_path) if os.path.isdir(pin_path) else None


def is_pin(kind):
    return isinstance(kind, str) and kind.startswith(PIN_KIND)


def hit_noun(container, kind):
    """How to NAME what was hit, in one phrase — a primary is not a pin."""
    if is_pin(kind):
        return f"the externally-consumed pin {container}/{PINS_DIR}/{kind[len(PIN_KIND):]}"
    return f"the PRIMARY checkout of {container}"


def hit_advice(container, kind):
    """The compliant move for this hit, in its own terms."""
    if is_pin(kind):
        return pin_advice(container, kind[len(PIN_KIND):])
    return worktree_advice(container)


def worktree_advice(project):
    """The exact commands to work correctly, in the canonical layout.

    SLUG, never `<slug>`: the angle brackets in a runnable command parse as a
    shell redirect in launch_critical_decide's own scanner, which then denies
    the agent for following this advice.
    """
    container = os.path.join(code_root(), project)
    return (
        "Work in a lane, then land through a ref:\n"
        f"  mkdir -p {container}/{WORKTREES_DIR}\n"
        f"  git -C {container}/main worktree add {container}/{WORKTREES_DIR}/SLUG -b SLUG\n"
        f"  # edit + commit in {container}/{WORKTREES_DIR}/SLUG, then land it:\n"
        f"  git -C {container}/main merge --ff-only SLUG\n"
        f"  # (plain `git fetch LANE BRANCH:refs/heads/main` cannot be used: main is checked out)\n"
    )


def pin_advice(project, name):
    """The compliant move against a pin — never mutate the current checkout.

    The current pin never moves. Advancing a consumer means creating a new
    detached, full-object-ID worktree from main and changing the consumer to
    that new path. Once every named consumer has moved, explicit verified
    retirement removes the old checkout and sidecar together.
    """
    container = os.path.join(code_root(), project)
    return (
        "A pin is not a lane. Do not edit it, and do not cut a worktree from it:\n"
        f"  cat {container}/{PINS_DIR}/{name}.pin        # who consumes it, on what terms\n"
        "To advance a consumer, leave this checkout untouched and create a new pin:\n"
        "  PIN_OBJECT_ID=FULL_GIT_OBJECT_ID\n"
        f"  git -C {container}/main worktree add --detach "
        f"{container}/{PINS_DIR}/$PIN_OBJECT_ID $PIN_OBJECT_ID\n"
        f"  # write {container}/{PINS_DIR}/$PIN_OBJECT_ID.pin, then update the consumer\n"
        "After read-only checks prove every named consumer moved, retire the old pin:\n"
        f"  pin-retire --consumer-main CONSUMER/main -- "
        f"{container}/{PINS_DIR}/{name}\n"
        "Raw removal stays denied; the old path and HEAD remain immutable until retirement.\n"
    )
