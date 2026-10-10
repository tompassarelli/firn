#!/usr/bin/env python3
"""Policy surface ownership and provider hook-binding checks."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import sys
import tomllib


UNIT = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
ACTIVATION_DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")
PERMISSION = re.compile(r"^(on|off)$")
ACTIVATION_SCHEMA = "north.agent-activation/v1"
REQUIRED_UNIT_FIELDS = {
    "id",
    "kind",
    "title",
    "triggerDescription",
    "permission",
    "active",
    "owner",
    "members",
    "supports",
    "distributions",
    "activationPaths",
}


class Contract:
    def __init__(self) -> None:
        self.errors: list[str] = []

    def reject(self, message: str) -> None:
        self.errors.append(message)


def normalized(text: str) -> str:
    return " ".join(text.split())


def digest(text: str) -> str:
    return hashlib.sha256(normalized(text).encode()).hexdigest()


def markdown_blocks(path: Path) -> list[tuple[str, str, str]]:
    lines = path.read_text().splitlines()
    section = "preamble"
    blocks: list[tuple[str, str, str]] = []
    paragraph: list[str] = []
    bullet: list[str] = []
    fenced = False

    def emit(parts: list[str]) -> None:
        if parts:
            text = normalized(" ".join(part.strip() for part in parts))
            blocks.append((section, digest(text), text))

    for line in lines:
        if line.startswith("```"):
            emit(paragraph)
            paragraph = []
            emit(bullet)
            bullet = []
            fenced = not fenced
            continue
        if fenced:
            continue
        if line.startswith("# "):
            emit(paragraph)
            paragraph = []
            emit(bullet)
            bullet = []
            continue
        if line.startswith("## "):
            emit(paragraph)
            paragraph = []
            emit(bullet)
            bullet = []
            section = line[3:].strip()
            continue
        if re.match(r"^#{3,6}\s", line) or line.startswith("    "):
            emit(paragraph)
            paragraph = []
            emit(bullet)
            bullet = []
            continue
        if re.match(r"^[-*+]\s+", line):
            emit(paragraph)
            paragraph = []
            emit(bullet)
            bullet = [line]
            continue
        if not line.strip():
            emit(paragraph)
            paragraph = []
            emit(bullet)
            bullet = []
            continue
        (bullet if bullet else paragraph).append(line)
    emit(paragraph)
    emit(bullet)
    return blocks


def check_surfaces(contract: Contract, surfaces: dict[str, Path]) -> None:
    seen: dict[str, tuple[str, str]] = {}
    for surface, path in surfaces.items():
        try:
            blocks = markdown_blocks(path)
        except OSError as exc:
            contract.reject(f"{surface} policy source is unreadable: {path}: {exc}")
            continue
        for section, block_digest, text in blocks:
            if block_digest in seen:
                other_surface, other_section = seen[block_digest]
                contract.reject(
                    f"{surface} [{section}] repeats the {other_surface} [{other_section}] "
                    f"block: {text[:80]}"
                )
                continue
            seen[block_digest] = (surface, section)


def command_identity(command: str) -> str:
    try:
        words = shlex.split(command)
    except ValueError:
        words = command.split()
    return Path(words[-1]).name if words else ""


def codex_bindings(path: Path, identity: str) -> tuple[list[str], list[str]]:
    data = tomllib.loads(path.read_text())
    events: list[str] = []
    commands: list[str] = []
    for event, groups in (data.get("hooks") or {}).items():
        if event == "managed_dir" or not isinstance(groups, list):
            continue
        for group in groups:
            matcher = group.get("matcher", "")
            for hook in group.get("hooks", []):
                command = hook.get("command", "")
                if command_identity(command) == identity:
                    events.append(f"{event}:{matcher}")
                    commands.append(command)
    return events, commands


def claude_bindings(path: Path, identity: str) -> tuple[list[str], list[str]]:
    data = json.loads(path.read_text())
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        raise ValueError("hooks must be an object")
    events: list[str] = []
    commands: list[str] = []
    for event, groups in hooks.items():
        if not isinstance(groups, list):
            raise ValueError(f"{event} hook groups must be an array")
        for group in groups:
            matcher = group.get("matcher", "")
            for hook in group.get("hooks", []):
                command = hook.get("command", "")
                if command_identity(command) == identity:
                    events.append(f"{event}:{matcher}")
                    commands.append(command)
    return events, commands


def check_provider_bindings(
    contract: Contract, policy: dict, requirements: Path, claude_hooks: Path
) -> None:
    seen_keys: set[str] = set()
    seen_units: set[str] = set()
    for guard in policy.get("guard", []):
        key = guard.get("key", "")
        unit = guard.get("unit", "")
        if key in seen_keys:
            contract.reject(f"duplicate provider guard key: {key}")
        seen_keys.add(key)
        if not UNIT.fullmatch(unit) or unit in seen_units:
            contract.reject(f"invalid or duplicate provider guard unit: {unit!r}")
        seen_units.add(unit)
        identity = guard.get("command", "")
        expected_command = guard.get("codex_command", "")
        try:
            events, commands = codex_bindings(requirements, identity)
        except (OSError, tomllib.TOMLDecodeError) as exc:
            contract.reject(f"{key}: Codex requirements are unreadable: {exc}")
            continue
        if sorted(events) != sorted(guard.get("codex", [])):
            contract.reject(f"{key}: Codex provider event reachability drift")
        if events and set(commands) != {expected_command}:
            contract.reject(f"{key}: Codex provider command drift")
        expected_claude_events = guard.get("claude", [])
        expected_claude_command = guard.get("claude_command", "")
        if expected_claude_events or expected_claude_command:
            try:
                claude_events, claude_commands = claude_bindings(
                    claude_hooks, identity
                )
            except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as exc:
                contract.reject(f"{key}: native-Claude hook projection is unreadable: {exc}")
                continue
            if sorted(claude_events) != sorted(expected_claude_events):
                contract.reject(f"{key}: native-Claude provider event reachability drift")
            if claude_events and set(claude_commands) != {expected_claude_command}:
                contract.reject(f"{key}: native-Claude provider command drift")


def activation_path() -> Path:
    explicit = os.environ.get("AGENT_POLICY_ACTIVATION")
    if explicit:
        return Path(explicit)
    state_root = os.environ.get("NORTH_AGENT_STATE_ROOT")
    if state_root:
        return Path(state_root) / "current/activation.json"
    return Path.home() / ".local/state/north/agents/current/activation.json"


def check_activation(
    contract: Contract,
    policy: dict,
    repo: Path,
) -> dict[str, dict]:
    path = activation_path()
    try:
        data = json.loads(path.read_text())
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        contract.reject(f"North activation generation is unreadable: {path}: {exc}")
        return {}
    if data.get("schema") != ACTIVATION_SCHEMA:
        contract.reject(f"North activation schema is not {ACTIVATION_SCHEMA}")
    if not ACTIVATION_DIGEST.fullmatch(data.get("catalogDigest", "")):
        contract.reject("North activation catalogDigest is invalid")
    if not ACTIVATION_DIGEST.fullmatch(data.get("generationId", "")):
        contract.reject("North activation generationId is invalid")
    units = data.get("units")
    if not isinstance(units, list):
        contract.reject("North activation units must be an array")
        return {}

    by_id: dict[str, dict] = {}
    for unit in units:
        if not isinstance(unit, dict):
            contract.reject("North activation contains a non-object unit")
            continue
        missing = REQUIRED_UNIT_FIELDS - unit.keys()
        if missing:
            contract.reject(
                f"North activation unit {unit.get('id')!r} lacks {sorted(missing)}"
            )
            continue
        unit_id = unit.get("id")
        kind = unit.get("kind")
        if not isinstance(unit_id, str) or not UNIT.fullmatch(unit_id):
            contract.reject(f"North activation has invalid unit id: {unit_id!r}")
            continue
        if unit_id in by_id:
            contract.reject(f"North activation duplicates global unit id {unit_id}")
        by_id[unit_id] = unit
        if kind not in {"skill", "hook", "module"}:
            contract.reject(f"North activation unit {unit_id} has invalid kind {kind!r}")
        permission = unit.get("permission")
        if not isinstance(permission, str) or not PERMISSION.fullmatch(permission):
            contract.reject(f"North activation unit {unit_id} has invalid permission")
        if type(unit.get("active")) is not bool:
            contract.reject(f"North activation unit {unit_id} has non-boolean activity")
        elif permission == "off" and unit.get("active") is True:
            contract.reject(
                f"North activation unit {unit_id} is active despite off permission"
            )
        for field in ("members", "supports", "distributions", "activationPaths"):
            if not isinstance(unit.get(field), list):
                contract.reject(f"North activation unit {unit_id} has non-array {field}")

        owner = unit.get("owner")
        if not isinstance(owner, dict) or not {"repo", "path"} <= set(owner):
            contract.reject(f"North activation unit {unit_id} has invalid owner")
            continue
        if owner.get("repo") == "nixos-config":
            relative = owner.get("path")
            if not isinstance(relative, str):
                contract.reject(f"NixOS-owned unit {unit_id} has invalid owner path")
                continue
            source = (repo / relative).resolve()
            try:
                source.relative_to(repo)
            except ValueError:
                contract.reject(f"NixOS-owned unit {unit_id} escapes its repository")
            if not source.exists():
                contract.reject(f"NixOS-owned unit {unit_id} source is absent: {relative}")

    for guard in policy.get("guard", []):
        unit_id = guard.get("unit", "")
        if unit_id not in by_id:
            contract.reject(f"provider-bound hook is absent from North activation: {unit_id}")
        elif by_id[unit_id].get("kind") != "hook":
            contract.reject(f"provider-bound unit is not a hook: {unit_id}")
    return by_id


def env_path(name: str, default: Path) -> Path:
    return Path(os.environ.get(name, str(default)))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--local", action="store_true")
    args = parser.parse_args()
    repo = args.repo.resolve()
    policy_path = env_path(
        "AGENT_POLICY_MANIFEST", repo / "dotfiles/agents/policy-owners.toml"
    )
    try:
        policy = tomllib.loads(policy_path.read_text())
    except (OSError, tomllib.TOMLDecodeError) as exc:
        print(f"policy ownership source is unreadable: {policy_path}: {exc}", file=sys.stderr)
        return 1

    bootstrap = env_path("AGENT_POLICY_BOOTSTRAP", repo / "dotfiles/agents/AGENTS.md")
    repo_agents = env_path("AGENT_POLICY_REPO_AGENTS", repo / "AGENTS.md")
    requirements = env_path(
        "AGENT_POLICY_CODEX_REQUIREMENTS", repo / "modules/codex/requirements.toml"
    )
    claude_hooks = env_path(
        "AGENT_POLICY_CLAUDE_HOOKS",
        repo / "modules/north-profile/claude-hooks.json",
    )

    contract = Contract()
    check_surfaces(contract, {"bootstrap": bootstrap, "repo": repo_agents})
    check_provider_bindings(contract, policy, requirements, claude_hooks)
    if args.local:
        check_activation(contract, policy, repo)

    if contract.errors:
        for error in contract.errors:
            print(f"policy-contract: {error}", file=sys.stderr)
        return 1
    print("policy-contract: ownership and Firn provider bindings passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
