#!/usr/bin/env python3
"""Deterministic policy ownership and Firn provider-binding checks."""

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


KEY = re.compile(r"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
UNIT = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
DIGEST = re.compile(r"^[0-9a-f]{64}$")
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


def check_claims(contract: Contract, policy: dict, surfaces: dict[str, Path]) -> None:
    claims = policy.get("claim", [])
    seen_keys: set[str] = set()
    mapped: dict[tuple[str, str], dict] = {}
    machine_digests: set[str] = set()
    approved_routes: dict[str, dict] = {}

    for route in policy.get("approved_route", []):
        key = route.get("key", "")
        owner = route.get("owner", "")
        text = route.get("text", "")
        slug = owner.split(":", 1)[1] if owner.startswith("skill:") else ""
        shape = re.fullmatch(r"- .{3,180} → `([a-z0-9-]+)`\.", text)
        if not KEY.fullmatch(key) or key in approved_routes:
            contract.reject(f"invalid or duplicate approved route key: {key!r}")
        elif not shape or shape.group(1) != slug:
            contract.reject(f"{key}: approved route has invalid owner or exact text")
        else:
            approved_routes[key] = route

    for claim in claims:
        key = claim.get("key", "")
        if not KEY.fullmatch(key):
            contract.reject(f"invalid policy key: {key!r}")
        if key in seen_keys:
            contract.reject(f"multiple owners for policy key {key}")
        seen_keys.add(key)
        role = claim.get("role")
        owner = claim.get("owner", "")
        scope = claim.get("scope")
        surface = claim.get("surface")
        block_digest = claim.get("digest")

        if role == "bootstrap":
            if owner != "bootstrap" or scope != "machine" or surface != "bootstrap":
                contract.reject(f"{key}: bootstrap role has invalid owner, scope, or surface")
        elif role == "route":
            if not owner.startswith("skill:") or scope != "machine" or surface != "bootstrap":
                contract.reject(f"{key}: route role must route machine policy to one skill")
            approved = approved_routes.get(key)
            if not approved or approved.get("owner") != owner:
                contract.reject(f"{key}: route is absent from the closed approved-route catalog")
        elif role == "owner":
            if owner.startswith("skill:"):
                if surface == "bootstrap" or block_digest:
                    contract.reject(f"{key}: skill-owned procedure remains in bootstrap")
                continue
            if not owner.startswith("repo:") or scope != owner or surface != "repo":
                contract.reject(f"{key}: owner role has invalid repository authority")
        else:
            contract.reject(f"{key}: role must be bootstrap, route, or owner")
            continue

        if not isinstance(block_digest, str) or not DIGEST.fullmatch(block_digest):
            contract.reject(f"{key}: mapped claim has no valid digest")
            continue
        identity = (surface, block_digest)
        if identity in mapped:
            contract.reject(f"multiple owners map {surface} block {block_digest}")
        mapped[identity] = claim
        if scope == "machine":
            machine_digests.add(block_digest)

    for surface, path in surfaces.items():
        try:
            blocks = markdown_blocks(path)
        except OSError as exc:
            contract.reject(f"{surface} policy source is unreadable: {path}: {exc}")
            continue
        observed: set[str] = set()
        for section, block_digest, text in blocks:
            claim = mapped.get((surface, block_digest))
            if not claim:
                contract.reject(f"unmapped normative block in {surface} [{section}]: {block_digest}")
                continue
            observed.add(block_digest)
            if claim.get("section") != section:
                contract.reject(
                    f"{claim['key']}: expected section {claim.get('section')!r}, "
                    f"observed {section!r}"
                )
            if surface == "repo" and claim.get("scope") == "machine":
                contract.reject(f"{claim['key']}: machine-global claim is in repo AGENTS.md")
            if surface == "repo" and block_digest in machine_digests:
                contract.reject(f"repo AGENTS.md duplicates machine-global claim {claim['key']}")
            if claim.get("role") == "route":
                approved = approved_routes.get(claim["key"])
                if not approved or text != approved.get("text"):
                    contract.reject(
                        f"{claim['key']}: route differs from the closed approved-route catalog"
                    )
        for (mapped_surface, block_digest), claim in mapped.items():
            if mapped_surface == surface and block_digest not in observed:
                contract.reject(f"{claim['key']}: mapped {surface} block is absent")


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
    expected_catalog_digest: str,
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
    elif data.get("catalogDigest") != expected_catalog_digest:
        contract.reject("North activation catalogDigest differs from the canonical catalog")
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


def resolve_catalog(
    contract: Contract, unit_ids: set[str], repo: Path
) -> tuple[str, dict[str, dict]]:
    try:
        payload = json.loads(activation_path().read_text())
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        contract.reject(f"North-v2 activation is unreadable: {activation_path()}: {exc}")
        return "", {}
    digest_value = payload.get("catalogDigest")
    units = payload.get("units")
    if not ACTIVATION_DIGEST.fullmatch(digest_value or "") or not isinstance(units, list):
        contract.reject("North-v2 activation returned an invalid catalog payload")
        return "", {}
    roots = {"nixos-config": str(repo)}
    if configured := os.environ.get("NORTH_REPO_ROOTS"):
        try:
            parsed_roots = json.loads(configured)
        except json.JSONDecodeError as exc:
            contract.reject(f"NORTH_REPO_ROOTS is invalid JSON: {exc}")
            return "", {}
        if not isinstance(parsed_roots, dict) or not all(
            isinstance(key, str) and isinstance(value, str)
            for key, value in parsed_roots.items()
        ):
            contract.reject("NORTH_REPO_ROOTS must map repository names to paths")
            return "", {}
        roots.update(parsed_roots)
    by_id: dict[str, dict] = {}
    for unit in units:
        if not isinstance(unit, dict) or not UNIT.fullmatch(unit.get("id", "")):
            contract.reject("North-v2 activation returned an invalid unit")
            continue
        unit_id = unit["id"]
        if unit_id not in unit_ids:
            continue
        if unit_id in by_id:
            contract.reject(f"North-v2 activation duplicated unit {unit_id}")
            continue
        owner = unit.get("owner")
        if not isinstance(owner, dict):
            contract.reject(f"North-v2 activation unit {unit_id} has no owner")
            continue
        owner_repo = owner.get("repo")
        owner_relative = owner.get("path")
        if not isinstance(owner_repo, str) or not isinstance(owner_relative, str):
            contract.reject(f"North-v2 activation unit {unit_id} has an invalid owner")
            continue
        root = Path(roots.get(owner_repo, Path.home() / "code" / owner_repo / "main"))
        resolved = (root / owner_relative).resolve()
        try:
            resolved.relative_to(root.resolve())
        except ValueError:
            contract.reject(f"North-v2 activation unit {unit_id} owner escapes its repository")
            continue
        enriched = dict(unit)
        enriched["resolvedOwnerPath"] = str(resolved)
        by_id[unit_id] = enriched
    return digest_value, by_id


def check_skill_evidence(
    contract: Contract,
    policy: dict,
    catalog: dict[str, dict],
    activation: dict[str, dict] | None = None,
) -> None:
    claims = policy.get("claim", [])
    approved_routes = {route.get("key"): route for route in policy.get("approved_route", [])}
    evidence = [
        entry
        for entry in claims
        if entry.get("owner", "").startswith("skill:")
    ] + list(policy.get("approved_route", []))

    for entry in evidence:
        key = entry.get("key", "")
        unit_id = entry.get("owner", "").split(":", 1)[1]
        catalog_unit = catalog.get(unit_id)
        if not catalog_unit or catalog_unit.get("kind") != "skill":
            contract.reject(f"{key}: destination skill is absent from the North catalog: {unit_id}")
            continue
        owner = catalog_unit.get("owner")
        section = entry.get("destination_section")
        block_digest = entry.get("destination_digest")
        if not isinstance(section, str) or not isinstance(block_digest, str) or not DIGEST.fullmatch(block_digest):
            contract.reject(f"{key}: destination skill section or digest is invalid")
            continue
        source_value = catalog_unit.get("resolvedOwnerPath")
        if not isinstance(source_value, str):
            contract.reject(f"{key}: North resolver omitted the destination source")
            continue
        source = Path(source_value)
        try:
            blocks = markdown_blocks(source)
        except (OSError, UnicodeError) as exc:
            contract.reject(f"{key}: destination skill is unreadable: {unit_id}: {exc}")
            continue
        if not any(
            observed_section == section and observed_digest == block_digest
            for observed_section, observed_digest, _ in blocks
        ):
            contract.reject(f"{key}: destination skill block is absent: {unit_id} [{section}]")

        if entry in claims and entry.get("role") == "route":
            approved = approved_routes.get(key)
            if approved and (
                approved.get("destination_section") != section
                or approved.get("destination_digest") != block_digest
            ):
                contract.reject(f"{key}: route destination differs from the approved catalog")

        if activation is None:
            continue
        activation_unit = activation.get(unit_id)
        if not activation_unit or activation_unit.get("kind") != "skill":
            contract.reject(f"{key}: destination skill is absent from North activation: {unit_id}")
            continue
        provenance = activation_unit.get("ownerProvenance")
        if activation_unit.get("owner") != owner:
            contract.reject(f"{key}: activation owner differs from the catalog owner")
        if provenance is None:
            contract.reject(f"{key}: destination skill lacks ownerProvenance")
        elif provenance != catalog_unit.get("ownerProvenance"):
            contract.reject(f"{key}: activation ownerProvenance differs from the North catalog")


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
    check_claims(contract, policy, {"bootstrap": bootstrap, "repo": repo_agents})
    check_provider_bindings(contract, policy, requirements, claude_hooks)
    skill_ids = {
        entry.get("owner", "").split(":", 1)[1]
        for entry in policy.get("claim", []) + policy.get("approved_route", [])
        if entry.get("owner", "").startswith("skill:")
    }
    catalog_digest, catalog = resolve_catalog(contract, skill_ids, repo)
    activation = None
    if args.local:
        activation = check_activation(contract, policy, repo, catalog_digest)
    check_skill_evidence(contract, policy, catalog, activation)

    if contract.errors:
        for error in contract.errors:
            print(f"policy-contract: {error}", file=sys.stderr)
        return 1
    print("policy-contract: ownership and Firn provider bindings passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
