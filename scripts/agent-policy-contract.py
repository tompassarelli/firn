#!/usr/bin/env python3
"""Policy surface ownership and provider hook-binding checks."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
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


PROVIDERS = ("claude", "codex")
EVENT_ORDER = (
    "PreToolUse",
    "PostToolUse",
    "PermissionRequest",
    "UserPromptSubmit",
    "Stop",
    "SubagentStop",
    "SessionStart",
)
HOOK_TIMEOUT = 10
RUNTIME = "/etc/codex/hooks/runtime"
SEARCH_PATH = f"PATH={RUNTIME}:/home/tom/.local/bin:/home/tom/.local/share/north/bin:/home/tom/.local/share/south/bin:/run/current-system/sw/bin"
DEFAULT_COMMAND = {
    "claude": (
        f"{RUNTIME}/env -u BASH_ENV -u ENV NORTH_AGENT_PYTHON={RUNTIME}/python3 "
        f"{SEARCH_PATH} {RUNTIME}/bash /home/tom/.agents/hooks/{{command}}"
    ),
    "codex": (
        f"{RUNTIME}/env -u BASH_ENV -u ENV {SEARCH_PATH} "
        f"{RUNTIME}/bash /etc/codex/hooks/{{command}}"
    ),
}
CODEX_HEADER = """allow_managed_hooks_only = true
allow_remote_control = false

[features]
hooks = true

[hooks]
managed_dir = "/etc/codex/hooks"
"""
GATE_CALL = re.compile(r"^[^#\n]*\bauthoring_guards_off\b[^#\n]*&&[ \t]*exit 0", re.M)
GATE_SOURCE = re.compile(r"^[^#\n]*authoring-killswitch\.sh", re.M)


def guard_command(guard: dict, provider: str) -> str:
    return guard.get(f"{provider}_command") or DEFAULT_COMMAND[provider].format(
        command=guard["command"]
    )


def wiring(policy: dict, provider: str) -> dict[str, list[tuple[str, list[str]]]]:
    events: dict[str, dict[str, list[str]]] = {}
    for guard in policy.get("guard", []):
        for binding in guard.get(provider, []):
            event, _, matcher = binding.partition(":")
            events.setdefault(event, {}).setdefault(matcher, []).append(
                guard_command(guard, provider)
            )
    return {
        event: list(events[event].items())
        for event in sorted(events, key=lambda e: EVENT_ORDER.index(e) if e in EVENT_ORDER else len(EVENT_ORDER))
    }


def render_claude(policy: dict, settings: dict) -> str:
    hooks = {
        event: [
            ({"matcher": matcher} if matcher else {})
            | {
                "hooks": [
                    {"type": "command", "command": command, "timeout": HOOK_TIMEOUT}
                    for command in commands
                ]
            }
            for matcher, commands in groups
        ]
        for event, groups in wiring(policy, "claude").items()
    }
    return json.dumps(settings | {"hooks": hooks}, indent=2) + "\n"


def render_codex(policy: dict) -> str:
    parts = [CODEX_HEADER]
    for event, groups in wiring(policy, "codex").items():
        for matcher, commands in groups:
            parts.append(f"\n[[hooks.{event}]]\n")
            if matcher:
                parts.append(f"matcher = {json.dumps(matcher)}\n")
            for command in commands:
                parts.append(
                    f"\n[[hooks.{event}.hooks]]\ntype = \"command\"\n"
                    f"command = {json.dumps(command)}\ntimeout = {HOOK_TIMEOUT}\n"
                )
    return "".join(parts)


def codex_adapters(policy: dict, catalog: dict) -> list[str]:
    guards = [g["command"] for g in policy.get("guard", []) if g.get("codex")]
    return sorted(set(guards) | {entry["path"] for entry in catalog["providerSupport"]})


def bnix_adapters(module: Path) -> list[str]:
    return sorted(
        re.findall(r'^[^;\n]*\(providerAdapter "([^"]+)"\)', module.read_text(), re.M)
    )


def hook_units(catalog: dict) -> dict[str, tuple[set[str], str]]:
    units: dict[str, tuple[set[str], str]] = {}
    for unit, entry in catalog["activation"].items():
        for distribution in entry.get("distributions", []):
            kind = distribution.get("type")
            if kind not in {"hook", "providerAdapter"}:
                continue
            owner = catalog["registrations"].get(unit, {}).get("owner", {})
            identity = (
                distribution.get("adapterId")
                if kind == "providerAdapter"
                else Path(owner.get("path", "")).name
            )
            targets = set(distribution.get("targets", [])) & set(PROVIDERS)
            units[unit] = (units.get(unit, (set(), ""))[0] | targets, identity)
    return units


def check_provider_bindings(contract: Contract, policy: dict, paths: dict[str, Path]) -> None:
    catalog = json.loads(paths["catalog"].read_text())
    units = hook_units(catalog)
    targets = {unit: entry[0] for unit, entry in units.items() if entry[0]}
    seen: set[str] = set()
    for guard in policy.get("guard", []):
        unit = guard.get("unit", "")
        if not UNIT.fullmatch(unit) or unit in seen:
            contract.reject(f"invalid or duplicate provider guard unit: {unit!r}")
            continue
        seen.add(unit)
        command = guard.get("command", "")
        if command != units.get(unit, (set(), None))[1]:
            contract.reject(
                f"{unit}: command {command!r} is not the hook catalog-config.json registers "
                f"for it ({units.get(unit, (set(), None))[1]!r})"
            )
        for provider in PROVIDERS:
            override = guard.get(f"{provider}_command", "")
            if override and Path(override.split()[-1]).name != command:
                contract.reject(f"{unit}: {provider}_command must run {command}")
            for binding in guard.get(provider, []):
                if binding.partition(":")[0] not in EVENT_ORDER:
                    contract.reject(f"{unit}: unknown {provider} event in {binding!r}")
        wired = {provider for provider in PROVIDERS if guard.get(provider)}
        if wired != targets.get(unit, set()):
            contract.reject(
                f"{unit}: wired for {sorted(wired)} but catalog-config.json targets "
                f"{sorted(targets.get(unit, set()))}"
            )
        for provider in PROVIDERS:
            if (provider in wired) == bool(guard.get(f"{provider}_absent")):
                contract.reject(
                    f"{unit}: give {provider}_absent a reason exactly when it has no "
                    f"{provider} binding"
                )
        source = paths["hooks"] / command
        if not source.is_file():
            contract.reject(f"{unit}: wired hook source is missing: {source}")
        elif not (
            GATE_SOURCE.search(source.read_text()) and GATE_CALL.search(source.read_text())
        ):
            contract.reject(
                f"{unit}: wired hook must source lib/authoring-killswitch.sh and exit 0 "
                "when authoring_guards_off"
            )
    for unit in sorted(set(targets) - seen):
        contract.reject(f"{unit}: registered hook targets {sorted(targets[unit])} but is unwired")

    try:
        settings = json.loads(paths["claude"].read_text())
    except (OSError, json.JSONDecodeError) as exc:
        contract.reject(f"Claude hook projection is unreadable: {exc}")
    else:
        settings.pop("hooks", None)
        if paths["claude"].read_text() != render_claude(policy, settings):
            contract.reject(
                f"{paths['claude']} differs from guard[]; run "
                "scripts/agent-policy-contract.py --repo . --write"
            )
    codex = paths["codex"].read_text()
    if codex != render_codex(policy):
        contract.reject(
            f"{paths['codex']} differs from guard[]; run "
            "scripts/agent-policy-contract.py --repo . --write"
        )
    if bnix_adapters(paths["bnix"]) != codex_adapters(policy, catalog):
        contract.reject(
            "modules/codex/default.bnix providerAdapter list must be exactly the Codex-bound "
            f"guards plus providerSupport: {codex_adapters(policy, catalog)}"
        )


def write_wiring(policy: dict, paths: dict[str, Path]) -> None:
    settings = json.loads(paths["claude"].read_text())
    settings.pop("hooks", None)
    paths["claude"].write_text(render_claude(policy, settings))
    paths["codex"].write_text(render_codex(policy))


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
    parser.add_argument("--write", action="store_true", help="regenerate provider hook wiring from guard[]")
    parser.add_argument("--codex-adapters", action="store_true", help="print the Codex provider adapter paths")
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
    paths = {
        "catalog": repo / "dotfiles/agents/catalog-config.json",
        "hooks": repo / "dotfiles/agents/hooks",
        "claude": env_path(
            "AGENT_POLICY_CLAUDE_HOOKS", repo / "modules/north-profile/claude-hooks.json"
        ),
        "codex": env_path(
            "AGENT_POLICY_CODEX_REQUIREMENTS", repo / "modules/codex/requirements.toml"
        ),
        "bnix": repo / "modules/codex/default.bnix",
    }
    if args.write:
        write_wiring(policy, paths)
    if args.codex_adapters:
        catalog = json.loads(paths["catalog"].read_text())
        print("\n".join(codex_adapters(policy, catalog)))
        return 0

    contract = Contract()
    check_surfaces(contract, {"bootstrap": bootstrap, "repo": repo_agents})
    check_provider_bindings(contract, policy, paths)
    if args.local:
        check_activation(contract, policy, repo)

    if contract.errors:
        for error in contract.errors:
            print(f"policy-contract: {error}", file=sys.stderr)
        return 1
    print("policy-contract: surface ownership and generated provider wiring passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
