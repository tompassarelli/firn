#!/usr/bin/env python3
"""Standalone adapter tests for the north-bridge Hermes plugin.

Runs without a live Hermes: loads the plugin's __init__.py directly and drives
the pure policy core (``evaluate_tool``), the lifecycle translator, the
additionalContext preservation path, the guard/lifecycle hook adapters, and the
startup self-check. Proves, per the done-bar:

  * every guard-CHAIN member is invoked in order (code-upstream/firn/north-clock
    for authoring; tripwire/firn/north-clock for terminal),
  * fail-closed guard DENY via a NON-ZERO exit,
  * fail-closed guard DENY via JSON on stdout (permissionDecision=deny, exit 0),
  * malformed-response DENY (non-empty non-JSON stdout),
  * unavailable DENY (guard missing) and exception DENY (guard raises),
  * degraded-enforcement DENY (missing enforcement cannot silently pass),
  * native delegate_task refusal — and that a BLOCKED native delegation is
    NEVER marked delegated,
  * north-mark-delegated fires ONLY when a real mcp__north__spawn /
    mcp__north__dispatch SUCCEEDS (status ok), never on error or other tools,
  * exact North lifecycle targets with the provider env UNSET (never
    AGENT_PROVIDER=hermes): session_start->north-on-spawn,
    tool_use->north-on-tooluse, session_end->north-on-stop,
    delegated->north-mark-delegated,
  * north-on-tooluse additionalContext is captured by tool_call_id and injected
    through transform_tool_result and pre_llm_call,
  * north-on-stop's {"decision":"block","reason":…} keep-going block is mapped
    through pre_verify.

Invoke:  python3 north-bridge.test.py   (exit 0 = all green)
"""

from __future__ import annotations

import importlib.util
import stat
import tempfile
import unittest
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_SPEC = importlib.util.spec_from_file_location("north_bridge", _HERE / "__init__.py")
nb = importlib.util.module_from_spec(_SPEC)
assert _SPEC and _SPEC.loader
_SPEC.loader.exec_module(nb)  # type: ignore[union-attr]

ALLOW = (0, "", True)  # exit 0, empty stdout, available → allow


def runner_returning(*, status=0, stdout="", available=True):
    """Guard runner that returns a fixed verdict, recording every call."""
    calls = []

    def _run(script, payload):
        calls.append((script, payload))
        return (status, stdout, available)

    _run.calls = calls  # type: ignore[attr-defined]
    return _run


def raising_runner(script, payload):
    raise RuntimeError("guard blew up")


DENY_JSON = '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"nope"}}'


# ---------------------------------------------------------------------------
# Fake lifecycle runner: (script, payload, env) -> (ok, stdout)
# ---------------------------------------------------------------------------


class FakeLifecycle:
    """Records lifecycle runs and returns scripted stdout keyed by script name."""

    def __init__(self, stdout_by_script=None, ok=True):
        self.calls = []  # list of (script, payload, env)
        self._stdout = stdout_by_script or {}
        self._ok = ok

    def __call__(self, script, payload, env):
        self.calls.append((script, payload, env))
        return (self._ok, self._stdout.get(script, ""))

    def scripts(self):
        return [c[0] for c in self.calls]


def install_fake_lifecycle(test, fake):
    """Patch the module default lifecycle runner for the duration of a test."""
    original = nb._real_lifecycle_runner
    nb._real_lifecycle_runner = fake
    test.addCleanup(lambda: setattr(nb, "_real_lifecycle_runner", original))


class DelegationTests(unittest.TestCase):
    def test_delegate_task_always_denied(self):
        r = nb.evaluate_tool("delegate_task", {"task": "x"}, runner_returning(), True)
        self.assertIsNotNone(r)
        self.assertEqual(r["action"], "block")
        self.assertIn("delegate_task", r["message"])

    def test_delegate_denied_even_with_allowing_guard_and_health(self):
        r = nb.evaluate_tool("delegate_task", {}, runner_returning(status=0), True)
        self.assertIsNotNone(r)

    def test_blocked_native_delegation_is_never_marked_delegated(self):
        # A blocked native delegate_task must NOT fire any North lifecycle
        # (marking it would falsely arm the Stop listener for work never spawned).
        fake = FakeLifecycle()
        install_fake_lifecycle(self, fake)
        decision = nb._on_pre_tool_call(tool_name="delegate_task", args={"task": "x"})
        self.assertIsNotNone(decision)
        self.assertEqual(decision["action"], "block")
        self.assertEqual(fake.calls, [], "blocked native delegation must not touch lifecycle")


class ChainMembershipTests(unittest.TestCase):
    def test_authoring_runs_full_chain_in_order(self):
        run = runner_returning()  # allow every member
        r = nb.evaluate_tool("write_file", {"path": "/tmp/f", "content": "x"}, run, True)
        self.assertIsNone(r)
        self.assertEqual([c[0] for c in run.calls], list(nb.AUTHORING_CHAIN))
        self.assertEqual(
            list(nb.AUTHORING_CHAIN),
            ["code-upstream-guard.sh", "firn-guard.sh"],
        )

    def test_patch_uses_authoring_chain(self):
        run = runner_returning()
        nb.evaluate_tool("patch", {"path": "/tmp/f"}, run, True)
        self.assertEqual([c[0] for c in run.calls], list(nb.AUTHORING_CHAIN))

    def test_terminal_runs_full_chain_in_order(self):
        run = runner_returning()
        r = nb.evaluate_tool("terminal", {"command": "ls"}, run, True)
        self.assertIsNone(r)
        self.assertEqual([c[0] for c in run.calls], list(nb.TERMINAL_CHAIN))
        self.assertEqual(
            list(nb.TERMINAL_CHAIN),
            ["tripwire-guard.sh", "firn-guard.sh"],
        )

    def test_process_uses_terminal_chain(self):
        run = runner_returning()
        nb.evaluate_tool("process", {"command": "ls"}, run, True)
        self.assertEqual([c[0] for c in run.calls], list(nb.TERMINAL_CHAIN))

    def test_first_deny_short_circuits_chain(self):
        run = runner_returning(status=2)
        r = nb.evaluate_tool("write_file", {"path": "/tmp/f"}, run, True)
        self.assertIsNotNone(r)
        self.assertEqual(len(run.calls), 1, "chain must short-circuit on first deny")


class FailClosedTests(unittest.TestCase):
    AUTHORING = ("write_file", "patch")
    TERMINAL = ("terminal", "process")

    def _all(self):
        return self.AUTHORING + self.TERMINAL

    def test_allow_when_every_member_allows(self):
        for tool in self._all():
            r = nb.evaluate_tool(tool, {"path": "/tmp/f", "command": "ls"},
                                 runner_returning(), True)
            self.assertIsNone(r, f"{tool} should be allowed when the chain allows")

    def test_deny_on_nonzero_exit(self):
        for tool in self._all():
            r = nb.evaluate_tool(tool, {"path": "/tmp/f", "command": "ls"},
                                 runner_returning(status=2), True)
            self.assertIsNotNone(r, f"{tool} must deny on guard exit 2")
            self.assertEqual(r["action"], "block")

    def test_deny_on_json_permissiondecision_deny_exit_zero(self):
        for tool in self._all():
            r = nb.evaluate_tool(tool, {"path": "/tmp/f", "command": "ls"},
                                 runner_returning(status=0, stdout=DENY_JSON), True)
            self.assertIsNotNone(r, f"{tool} must deny on stdout permissionDecision=deny")

    def test_deny_on_malformed_stdout(self):
        for tool in self._all():
            r = nb.evaluate_tool(tool, {"path": "/tmp/f", "command": "ls"},
                                 runner_returning(status=0, stdout="not json {"), True)
            self.assertIsNotNone(r, f"{tool} must fail closed on malformed guard output")

    def test_deny_when_unavailable(self):
        for tool in self._all():
            r = nb.evaluate_tool(tool, {"path": "/tmp/f", "command": "ls"},
                                 runner_returning(available=False), True)
            self.assertIsNotNone(r, f"{tool} must fail closed when a guard is unavailable")

    def test_deny_when_guard_raises(self):
        for tool in self._all():
            r = nb.evaluate_tool(tool, {"path": "/tmp/f", "command": "ls"},
                                 raising_runner, True)
            self.assertIsNotNone(r, f"{tool} must fail closed when a guard raises")
            self.assertEqual(r["action"], "block")

    def test_deny_when_enforcement_degraded(self):
        for tool in self._all():
            r = nb.evaluate_tool(tool, {"path": "/tmp/f", "command": "ls"},
                                 runner_returning(), False)
            self.assertIsNotNone(r, f"{tool} must deny when enforcement degraded")
            self.assertIn("DEGRADED", r["message"])

    def test_json_allow_envelope_permits(self):
        allow_env = '{"hookSpecificOutput":{"permissionDecision":"allow"}}'
        r = nb.evaluate_tool("write_file", {"path": "/tmp/f"},
                             runner_returning(status=0, stdout=allow_env), True)
        self.assertIsNone(r)


class UnguardedTests(unittest.TestCase):
    def test_read_file_not_guarded(self):
        r = nb.evaluate_tool("read_file", {"path": "/tmp/f"}, raising_runner, False)
        self.assertIsNone(r, "non-guarded tools are unaffected even when degraded")


class LifecycleTargetTests(unittest.TestCase):
    """Exact North hook script per event, with the provider env UNSET."""

    def _capture(self, stdout=""):
        seen = []

        def runner(script, payload, env):
            seen.append((script, payload, env))
            return (True, stdout)

        return runner, seen

    def test_session_start_targets_north_on_spawn(self):
        runner, seen = self._capture()
        self.assertTrue(nb.emit_lifecycle("session_start", {"session_id": "s"}, runner))
        self.assertEqual(seen[0][0], "north-on-spawn")

    def test_tool_use_targets_north_on_tooluse(self):
        runner, seen = self._capture()
        nb.emit_lifecycle("tool_use", {}, runner)
        self.assertEqual(seen[0][0], "north-on-tooluse")

    def test_session_end_targets_north_on_stop(self):
        runner, seen = self._capture()
        nb.emit_lifecycle("session_end", {}, runner)
        self.assertEqual(seen[0][0], "north-on-stop")

    def test_delegated_targets_north_mark_delegated(self):
        runner, seen = self._capture()
        nb.emit_lifecycle("delegated", {}, runner)
        self.assertEqual(seen[0][0], "north-mark-delegated")

    def test_provider_is_never_set_on_any_lifecycle(self):
        for event in nb.LIFECYCLE_SCRIPTS:
            runner, seen = self._capture()
            nb.emit_lifecycle(event, {}, runner)
            env = seen[0][2]
            self.assertNotIn(
                "AGENT_PROVIDER", env,
                f"{event} must not set AGENT_PROVIDER (provider stays unobserved)",
            )
            self.assertEqual(env, {}, f"{event} lifecycle env overlay must be empty")

    def test_mapping_matches_task_contract(self):
        self.assertEqual(
            nb.LIFECYCLE_SCRIPTS,
            {
                "session_start": "north-on-spawn",
                "tool_use": "north-on-tooluse",
                "session_end": "north-on-stop",
                "delegated": "north-mark-delegated",
            },
        )

    def test_unknown_event_is_noop(self):
        runner, seen = self._capture()
        self.assertFalse(nb.emit_lifecycle("bogus", {}, runner))
        self.assertEqual(seen, [])

    def test_lifecycle_never_raises(self):
        def boom(script, payload, env):
            raise RuntimeError("north down")

        self.assertFalse(nb.emit_lifecycle("session_end", {}, boom))

    def test_run_lifecycle_captures_stdout(self):
        runner, _ = self._capture(stdout="hello")
        ok, out = nb.run_lifecycle("tool_use", {}, runner)
        self.assertTrue(ok)
        self.assertEqual(out, "hello")

    def test_run_lifecycle_tolerates_bool_only_runner(self):
        def legacy(script, payload, env):
            return True

        ok, out = nb.run_lifecycle("tool_use", {}, legacy)
        self.assertTrue(ok)
        self.assertEqual(out, "")


class MarkDelegatedTests(unittest.TestCase):
    """north-mark-delegated fires only on a SUCCESSFUL North MCP spawn/dispatch."""

    def setUp(self):
        nb._pending_context.clear()

    def test_mark_on_successful_mcp_spawn(self):
        fake = FakeLifecycle()
        install_fake_lifecycle(self, fake)
        nb._on_post_tool_call(tool_name="mcp__north__spawn", status="ok",
                              tool_call_id="t1", result="{}")
        self.assertIn("north-mark-delegated", fake.scripts())

    def test_mark_on_successful_mcp_dispatch(self):
        fake = FakeLifecycle()
        install_fake_lifecycle(self, fake)
        nb._on_post_tool_call(tool_name="mcp__north__dispatch", status="ok",
                              tool_call_id="t2", result="{}")
        self.assertIn("north-mark-delegated", fake.scripts())

    def test_no_mark_on_failed_mcp_spawn(self):
        fake = FakeLifecycle()
        install_fake_lifecycle(self, fake)
        nb._on_post_tool_call(tool_name="mcp__north__spawn", status="error",
                              tool_call_id="t3", result='{"error":"x"}')
        self.assertNotIn("north-mark-delegated", fake.scripts())

    def test_no_mark_on_other_tool(self):
        fake = FakeLifecycle()
        install_fake_lifecycle(self, fake)
        nb._on_post_tool_call(tool_name="read_file", status="ok",
                              tool_call_id="t4", result="{}")
        self.assertNotIn("north-mark-delegated", fake.scripts())
        # north-on-tooluse still runs the mail heartbeat on every tool.
        self.assertIn("north-on-tooluse", fake.scripts())


class AdditionalContextTests(unittest.TestCase):
    """north-on-tooluse additionalContext is preserved and re-injected."""

    TOOLUSE_CTX = ('{"hookSpecificOutput":{"hookEventName":"PostToolUse",'
                   '"additionalContext":"peer mail: ping"}}')

    def setUp(self):
        nb._pending_context.clear()

    def test_transform_injects_context_for_matching_tool_call(self):
        fake = FakeLifecycle(stdout_by_script={"north-on-tooluse": self.TOOLUSE_CTX})
        install_fake_lifecycle(self, fake)
        nb._on_post_tool_call(tool_name="read_file", status="ok",
                              tool_call_id="tc1", result="orig")
        out = nb._on_transform_tool_result(tool_name="read_file", result="orig",
                                           tool_call_id="tc1")
        self.assertIsNotNone(out)
        self.assertIn("orig", out)
        self.assertIn("peer mail: ping", out)
        # Consumed — a second transform sees nothing.
        self.assertIsNone(nb._on_transform_tool_result(tool_name="read_file",
                                                       result="orig", tool_call_id="tc1"))

    def test_pre_llm_call_drains_uninjected_context(self):
        fake = FakeLifecycle(stdout_by_script={"north-on-tooluse": self.TOOLUSE_CTX})
        install_fake_lifecycle(self, fake)
        nb._on_post_tool_call(tool_name="read_file", status="ok",
                              tool_call_id="tc9", result="orig")
        injected = nb._on_pre_llm_call()
        self.assertIsInstance(injected, dict)
        self.assertIn("peer mail: ping", injected["context"])
        # Drained — nothing left.
        self.assertIsNone(nb._on_pre_llm_call())

    def test_no_context_no_injection(self):
        fake = FakeLifecycle(stdout_by_script={"north-on-tooluse": ""})
        install_fake_lifecycle(self, fake)
        nb._on_post_tool_call(tool_name="read_file", status="ok",
                              tool_call_id="tcx", result="orig")
        self.assertIsNone(nb._on_transform_tool_result(tool_name="read_file",
                                                       result="orig", tool_call_id="tcx"))
        self.assertIsNone(nb._on_pre_llm_call())

    def test_context_is_bounded(self):
        huge = 'x' * (nb._MAX_CONTEXT_CHARS * 3)
        nb._remember_context("k", huge)
        self.assertLessEqual(len(nb._pending_context["k"]), nb._MAX_CONTEXT_CHARS)

    def test_pending_entries_are_bounded(self):
        nb._pending_context.clear()
        for i in range(nb._MAX_PENDING_ENTRIES + 20):
            nb._remember_context(f"k{i}", "c")
        self.assertLessEqual(len(nb._pending_context), nb._MAX_PENDING_ENTRIES)


class PreVerifyTests(unittest.TestCase):
    """north-on-stop's keep-going decision maps through pre_verify."""

    def test_block_decision_keeps_agent_going(self):
        block = '{"decision":"block","reason":"arm the listener"}'
        fake = FakeLifecycle(stdout_by_script={"north-on-stop": block})
        install_fake_lifecycle(self, fake)
        out = nb._on_pre_verify(session_id="s")
        self.assertEqual(out, {"decision": "block", "reason": "arm the listener"})
        self.assertIn("north-on-stop", fake.scripts())

    def test_empty_decision_lets_turn_finish(self):
        fake = FakeLifecycle(stdout_by_script={"north-on-stop": ""})
        install_fake_lifecycle(self, fake)
        self.assertIsNone(nb._on_pre_verify(session_id="s"))

    def test_malformed_decision_lets_turn_finish(self):
        fake = FakeLifecycle(stdout_by_script={"north-on-stop": "not json"})
        install_fake_lifecycle(self, fake)
        self.assertIsNone(nb._on_pre_verify(session_id="s"))

    def test_failed_stop_run_lets_turn_finish(self):
        fake = FakeLifecycle(ok=False)
        install_fake_lifecycle(self, fake)
        self.assertIsNone(nb._on_pre_verify(session_id="s"))


class SelfCheckTests(unittest.TestCase):
    CHAIN = ("code-upstream-guard.sh", "firn-guard.sh", "tripwire-guard.sh")

    def _make_guard_dir(self, tmp, include=None, include_support=True):
        include = self.CHAIN if include is None else include
        gdir = Path(tmp)
        for name in include:
            p = gdir / name
            p.write_text("#!/usr/bin/env bash\nexit 0\n")
            p.chmod(p.stat().st_mode | stat.S_IXUSR)
        if include_support:
            libdir = gdir / "lib"
            libdir.mkdir(exist_ok=True)
            (libdir / "authoring-killswitch.sh").write_text("# shell lib\n")
        return gdir

    def test_ok_when_all_present(self):
        with tempfile.TemporaryDirectory() as tmp:
            gdir = self._make_guard_dir(tmp)
            ok, problems = nb.selfcheck(guard_dir=gdir, north_bin="/bin/sh")
            self.assertTrue(ok, f"expected clean self-check, got {problems}")
            self.assertEqual(problems, [])

    def test_degraded_when_a_chain_guard_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            gdir = self._make_guard_dir(
                tmp, include=("code-upstream-guard.sh", "firn-guard.sh"))
            ok, problems = nb.selfcheck(guard_dir=gdir, north_bin="/bin/sh")
            self.assertFalse(ok)
            self.assertTrue(any("tripwire-guard.sh" in p for p in problems))

    def test_degraded_when_killswitch_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            gdir = self._make_guard_dir(tmp, include_support=False)
            ok, problems = nb.selfcheck(guard_dir=gdir, north_bin="/bin/sh")
            self.assertFalse(ok)
            self.assertTrue(any("authoring-killswitch.sh" in p for p in problems))

    def test_degraded_when_north_absent(self):
        with tempfile.TemporaryDirectory() as tmp:
            gdir = self._make_guard_dir(tmp)
            ok, problems = nb.selfcheck(guard_dir=gdir, north_bin="north-does-not-exist-xyzzy")
            self.assertFalse(ok)
            self.assertTrue(any("north" in p for p in problems))


class ManifestTests(unittest.TestCase):
    def test_plugin_yaml_hooks_are_registered(self):
        import re

        manifest = (_HERE / "plugin.yaml").read_text()
        hooks = re.findall(r"^\s*-\s*(\w+)\s*$", manifest, re.MULTILINE)
        for expected in ("pre_tool_call", "post_tool_call", "transform_tool_result",
                         "pre_llm_call", "pre_verify", "on_session_start", "on_session_end"):
            self.assertIn(expected, hooks, f"manifest must declare {expected}")

        registered = []

        class Ctx:
            def register_hook(self, name, cb):
                registered.append(name)

        nb.register(Ctx())
        for h in hooks:
            self.assertIn(h, registered, f"manifest hook {h} not registered")
        # And every registered hook is a valid Hermes hook name.
        for h in registered:
            self.assertIn(h, hooks, f"registered hook {h} missing from manifest")


if __name__ == "__main__":
    unittest.main(verbosity=2)
