#!/usr/bin/env python3
"""Deterministic ownership and projection checks for agent policy."""

from __future__ import annotations

import argparse
import csv
import hashlib
import os
from pathlib import Path
import re
import shlex
import sys
import tomllib


KEY = re.compile(r"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
SKILL = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


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


def parse_shell_array(text: str, name: str) -> list[str]:
    match = re.search(rf"^{re.escape(name)}=\((.*?)\)\s*$", text, re.M | re.S)
    if not match:
        raise ValueError(f"missing {name} array")
    return shlex.split(match.group(1), comments=True)


def parse_skill_sources(text: str, home: Path, repo: Path) -> dict[str, Path]:
    start = text.find("\nskill_source()")
    end = text.find("\n}\n", start + 1)
    if start < 0 or end < 0:
        raise ValueError("missing skill_source function")
    body = text[start:end]
    north = home / "code/north/main"
    sources: dict[str, Path] = {}
    for name, raw in re.findall(
        r'^\s*([a-z0-9-]+)\)\s+echo\s+"([^"]+)"\s*;;', body, re.M
    ):
        value = (
            raw.replace("$HOME", str(home))
            .replace("$NORTH", str(north))
            .replace("$NIXOS_CONFIG", str(repo))
        )
        sources[name] = Path(value)
    return sources


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


def registry_rows(path: Path) -> dict[str, dict[str, str]]:
    lines = [line for line in path.read_text().splitlines() if line and not line.startswith("#")]
    reader = csv.DictReader(lines, delimiter="\t")
    return {row["id"]: row for row in reader}


def north_chains(path: Path) -> dict[str, list[str]]:
    text = path.read_text()
    constants = dict(re.findall(r'^const\s+([A-Z_]+)\s*=\s*"([^"]+)";', text, re.M))
    result: dict[str, list[str]] = {}
    for name in ("EDIT_GUARDS", "BASH_GUARDS", "WORKER_BASH_GUARDS"):
        match = re.search(
            rf"const\s+{name}\s*=\s*resolveManagedGuardChain\(\[(.*?)\]\);",
            text,
            re.S,
        )
        if not match:
            raise ValueError(f"missing North {name}")
        values: list[str] = []
        for quoted, symbol in re.findall(r'"([^"]+)"|\b([A-Z][A-Z_]*)\b', match.group(1)):
            values.append(quoted or constants.get(symbol, symbol))
        result[name] = values
    return result


def check_claims(contract: Contract, manifest: dict, surfaces: dict[str, Path]) -> None:
    claims = manifest.get("claim", [])
    seen_keys: set[str] = set()
    mapped: dict[tuple[str, str], dict] = {}
    machine_digests: set[str] = set()
    approved_routes: dict[str, dict] = {}

    for route in manifest.get("approved_route", []):
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
        section = claim.get("section")

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

        if not isinstance(block_digest, str) or not re.fullmatch(r"[0-9a-f]{64}", block_digest):
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
            identity = (surface, block_digest)
            claim = mapped.get(identity)
            if not claim:
                contract.reject(f"unmapped normative block in {surface} [{section}]: {block_digest}")
                continue
            observed.add(block_digest)
            if claim.get("section") != section:
                contract.reject(
                    f"{claim['key']}: expected section {claim.get('section')!r}, observed {section!r}"
                )
            if surface == "repo" and claim.get("scope") == "machine":
                contract.reject(f"{claim['key']}: machine-global claim is in repo AGENTS.md")
            if surface == "repo" and block_digest in machine_digests:
                contract.reject(f"repo AGENTS.md duplicates machine-global claim {claim['key']}")
            if claim.get("role") == "route":
                approved = approved_routes.get(claim["key"])
                if not approved or text != approved.get("text"):
                    contract.reject(f"{claim['key']}: route differs from the closed approved-route catalog")
        for (mapped_surface, block_digest), claim in mapped.items():
            if mapped_surface == surface and block_digest not in observed:
                contract.reject(f"{claim['key']}: mapped {surface} block is absent")


def check_skill_evidence(
    contract: Contract, manifest: dict, switchboard: Path, repo: Path
) -> None:
    try:
        text = switchboard.read_text()
        inventory = set(parse_shell_array(text, "SKILLS"))
        sources = parse_skill_sources(text, Path.home(), repo)
    except (OSError, ValueError) as exc:
        contract.reject(f"switchboard skill inventory is unreadable: {exc}")
        return

    evidence = [
        entry
        for entry in manifest.get("claim", [])
        if entry.get("owner", "").startswith("skill:")
    ] + list(manifest.get("approved_route", []))
    for entry in evidence:
        key = entry.get("key", "")
        owner = entry.get("owner", "").split(":", 1)[1]
        section = entry.get("destination_section")
        block_digest = entry.get("destination_digest")
        if owner not in inventory or owner not in sources:
            contract.reject(f"{key}: destination skill is not registered: {owner}")
            continue
        if not isinstance(section, str) or not isinstance(block_digest, str) or not re.fullmatch(r"[0-9a-f]{64}", block_digest):
            contract.reject(f"{key}: destination skill section or digest is invalid")
            continue
        skill_file = sources[owner] / "SKILL.md"
        try:
            blocks = markdown_blocks(skill_file)
        except OSError as exc:
            contract.reject(f"{key}: destination skill is unreadable: {owner}: {exc}")
            continue
        if not any(observed_section == section and observed_digest == block_digest for observed_section, observed_digest, _ in blocks):
            contract.reject(f"{key}: destination skill block is absent: {owner} [{section}]")

        if entry in manifest.get("claim", []) and entry.get("role") == "route":
            approved = next(
                (route for route in manifest.get("approved_route", []) if route.get("key") == key),
                None,
            )
            if approved and (
                approved.get("destination_section") != section
                or approved.get("destination_digest") != block_digest
            ):
                contract.reject(f"{key}: route destination differs from the approved catalog")


def check_skills(
    contract: Contract,
    manifest: dict,
    switchboard: Path,
    repo: Path,
    activity: Path | None,
    north_catalog: Path | None,
    shared_farm: Path | None,
    provider_farms: list[tuple[str, Path]],
    local: bool,
) -> None:
    try:
        text = switchboard.read_text()
        inventory = parse_shell_array(text, "SKILLS")
        sources = parse_skill_sources(text, Path.home(), repo)
    except (OSError, ValueError) as exc:
        contract.reject(f"switchboard skill inventory is unreadable: {exc}")
        return
    if len(inventory) != len(set(inventory)):
        contract.reject("switchboard SKILLS contains duplicate identities")
    missing_mappings = sorted(set(inventory) - set(sources))
    if missing_mappings:
        contract.reject(f"switchboard skills lack source mappings: {', '.join(missing_mappings)}")

    owners = {
        claim.get("owner", "").split(":", 1)[1]
        for claim in manifest.get("claim", [])
        if claim.get("owner", "").startswith("skill:")
    }
    for owner in sorted(owners):
        if owner not in inventory:
            contract.reject(f"policy owner skill is absent from switchboard inventory: {owner}")
        source = sources.get(owner)
        if not source or not os.access(source / "SKILL.md", os.R_OK):
            contract.reject(f"policy owner skill is unreadable: {owner}")

    if not local:
        return
    if activity is None or not activity.is_file():
        contract.reject(f"active skill projection is unreadable: {activity}")
        return
    active: set[str] = set()
    seen: set[str] = set()
    for line in activity.read_text().splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[0] == "skill":
            name, state = parts[1], parts[2]
            if name in seen:
                contract.reject(f"active skill projection duplicates {name}")
            seen.add(name)
            if name not in inventory:
                contract.reject(f"active skill is stale or absent from inventory: {name}")
            if state not in {"on", "off"}:
                contract.reject(f"active skill projection has invalid state for {name}: {state}")
            if state == "on":
                active.add(name)
    for name in sorted(active | owners):
        source = sources.get(name)
        skill_file = source / "SKILL.md" if source else None
        if not skill_file or not os.access(skill_file, os.R_OK):
            contract.reject(f"active skill source is unreadable: {name}")

    if north_catalog is not None and shared_farm is not None:
        if not north_catalog.is_dir():
            contract.reject(f"North source skill catalog is unreadable: {north_catalog}")
        elif not shared_farm.is_dir():
            contract.reject(f"shared skill farm is unreadable: {shared_farm}")
        else:
            catalog = {
                entry.name: entry
                for entry in north_catalog.iterdir()
                if entry.is_dir() and os.access(entry / "SKILL.md", os.R_OK)
            }
            observed = {
                entry.name: entry
                for entry in shared_farm.iterdir()
                if not entry.name.startswith(".")
            }
            if set(catalog) != set(observed):
                contract.reject(
                    "shared skill farm and North source catalog differ: "
                    f"catalog={sorted(catalog)} farm={sorted(observed)}"
                )
            for name in sorted(set(catalog) & set(observed)):
                if not os.access(observed[name] / "SKILL.md", os.R_OK):
                    contract.reject(f"shared skill farm has unreadable skill {name}")
                elif observed[name].resolve() != catalog[name].resolve():
                    contract.reject(
                        f"shared skill {name} points to {observed[name].resolve()}, "
                        f"expected {catalog[name].resolve()}"
                    )

    for label, farm in provider_farms:
        if not farm.is_dir():
            contract.reject(f"{label} skill farm is unreadable: {farm}")
            continue
        for name in sorted(active):
            entry = farm / name
            source = sources.get(name)
            if not source or not os.access(entry / "SKILL.md", os.R_OK):
                contract.reject(f"{label} skill farm is missing active skill {name}")
            elif entry.resolve() != source.resolve():
                contract.reject(f"{label} skill {name} points to {entry.resolve()}, expected {source.resolve()}")
        for name in sorted(set(inventory) - active):
            entry = farm / name
            source = sources.get(name)
            if entry.is_symlink() and source and entry.resolve() == source.resolve():
                contract.reject(f"{label} skill farm retains inactive skill {name}")


def check_projections(contract: Contract, source: Path, projections: list[Path]) -> None:
    try:
        expected = source.read_bytes()
    except OSError as exc:
        contract.reject(f"bootstrap source is unreadable: {source}: {exc}")
        return
    for projection in projections:
        try:
            actual = projection.read_bytes()
        except OSError as exc:
            contract.reject(f"agent policy projection is unreadable: {projection}: {exc}")
            continue
        if actual != expected:
            contract.reject(f"agent policy projection digest mismatch: {projection}")


def check_guards(
    contract: Contract,
    manifest: dict,
    switchboard: Path,
    requirements: Path,
    registry: Path,
    harness: Path,
) -> None:
    try:
        switchboard_hooks = set(parse_shell_array(switchboard.read_text(), "HOOKS"))
        rows = registry_rows(registry)
        chains = north_chains(harness)
    except (OSError, ValueError, KeyError) as exc:
        contract.reject(f"guard identity sources are unreadable: {exc}")
        return
    guards = manifest.get("guard", [])
    keys: set[str] = set()
    mapped_registry: set[str] = set()
    for guard in guards:
        key = guard.get("key", "")
        if key in keys:
            contract.reject(f"duplicate guard semantic key: {key}")
        keys.add(key)
        switchboard_id = guard.get("switchboard", "")
        if switchboard_id not in switchboard_hooks:
            contract.reject(f"{key}: switchboard hook identity is absent: {switchboard_id}")
        identity = guard.get("command", "")
        codex_command = guard.get("codex_command", "")
        try:
            actual_codex, codex_commands = codex_bindings(requirements, identity)
        except (OSError, tomllib.TOMLDecodeError) as exc:
            contract.reject(f"{key}: Codex guard table is unreadable: {exc}")
            actual_codex = []
        if sorted(actual_codex) != sorted(guard.get("codex", [])) or (
            actual_codex and set(codex_commands) != {codex_command}
        ):
            contract.reject(f"{key}: Codex guard identity or reachability drift")
        registry_id = guard.get("north_registry", "")
        mapped_registry.add(registry_id)
        row = rows.get(registry_id)
        if not row or row.get("kind") != "deny" or row.get("path") != guard.get("north_path") or row.get("events") != guard.get("north_events"):
            contract.reject(f"{key}: North guard registry identity drift")
        actual_chains = sorted(
            name
            for name, values in chains.items()
            if identity in {Path(value).name for value in values}
        )
        if actual_chains != sorted(guard.get("north_chains", [])):
            contract.reject(f"{key}: North worker guard reachability drift")
    deny_registry = {name for name, row in rows.items() if row.get("kind") == "deny"}
    if mapped_registry != deny_registry:
        contract.reject(
            "guard ownership manifest and North deny registry differ: "
            f"manifest={sorted(mapped_registry)} registry={sorted(deny_registry)}"
        )


def env_path(name: str, default: Path) -> Path:
    return Path(os.environ.get(name, str(default)))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--local", action="store_true")
    args = parser.parse_args()
    repo = args.repo.resolve()
    manifest_path = env_path("AGENT_POLICY_MANIFEST", repo / "dotfiles/agents/policy-owners.toml")
    try:
        manifest = tomllib.loads(manifest_path.read_text())
    except (OSError, tomllib.TOMLDecodeError) as exc:
        print(f"policy ownership manifest is unreadable: {manifest_path}: {exc}", file=sys.stderr)
        return 1

    bootstrap = env_path("AGENT_POLICY_BOOTSTRAP", repo / "dotfiles/agents/AGENTS.md")
    repo_agents = env_path("AGENT_POLICY_REPO_AGENTS", repo / "AGENTS.md")
    switchboard = env_path("AGENT_POLICY_SWITCHBOARD", repo / "dotfiles/bin/agents")
    requirements = env_path("AGENT_POLICY_CODEX_REQUIREMENTS", repo / "modules/codex/requirements.toml")
    north_profile = env_path("AGENT_POLICY_NORTH_PROFILE", Path.home() / "code/north/main/profiles/tom")
    north_harness = env_path("AGENT_POLICY_NORTH_HARNESS", Path.home() / "code/north/main/sdk/src/harness.ts")

    contract = Contract()
    check_claims(contract, manifest, {"bootstrap": bootstrap, "repo": repo_agents})
    check_skill_evidence(contract, manifest, switchboard, repo)
    check_guards(
        contract,
        manifest,
        switchboard,
        requirements,
        north_profile / "hooks/registry.tsv",
        north_harness,
    )
    if args.local:
        activity = env_path("AGENT_POLICY_ACTIVITY", Path.home() / ".config/agents/activity.conf")
        shared_farm = env_path("AGENT_POLICY_SHARED_SKILLS", Path.home() / ".agents/skills")
        provider_farms = [
            ("Codex", env_path("AGENT_POLICY_CODEX_SKILLS", Path.home() / ".codex/skills")),
        ]
        check_skills(
            contract,
            manifest,
            switchboard,
            repo,
            activity,
            north_profile / "skills",
            shared_farm,
            provider_farms,
            True,
        )
        projections = [
            env_path("AGENT_POLICY_STATE_AGENTS", Path.home() / ".config/agents/AGENTS.md"),
            env_path("AGENT_POLICY_AGENTS_PROJECTION", Path.home() / ".agents/AGENTS.md"),
            env_path("AGENT_POLICY_CODEX_PROJECTION", Path.home() / ".codex/AGENTS.md"),
        ]
        check_projections(contract, bootstrap, projections)
    else:
        check_skills(contract, manifest, switchboard, repo, None, None, None, [], False)

    if contract.errors:
        for error in contract.errors:
            print(f"policy-contract: {error}", file=sys.stderr)
        return 1
    print("policy-contract: ownership, reachability, and drift checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
