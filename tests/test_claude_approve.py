"""
Unit tests for scripts/claude-approve.py

Mocks all subprocess calls and socket I/O so tests are hermetic and run
on any platform (Linux CI, macOS, etc.).
"""

import importlib.util
import io
import json
import os
import socket
import sys
import unittest
from unittest.mock import MagicMock, patch, call

# ── Load the hook script as a module (its name contains a hyphen) ─────────────

_SCRIPT = os.path.join(os.path.dirname(__file__), "..", "scripts", "claude-approve.py")
_spec = importlib.util.spec_from_file_location("claude_approve", _SCRIPT)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
ca = _mod  # short alias


# ═════════════════════════════════════════════════════════════════════════════
# Helpers
# ═════════════════════════════════════════════════════════════════════════════

def _ioreg_output(idle_ns: int) -> str:
    """Fake ioreg stdout with a HIDIdleTime entry."""
    return f'      "HIDIdleTime" = {idle_ns}\n'


def _make_subprocess_result(stdout: str = "", returncode: int = 0) -> MagicMock:
    result = MagicMock()
    result.stdout = stdout
    result.returncode = returncode
    return result


def _run_main(stdin_json: dict, *, subprocess_side_effect=None,
              socket_response: dict | None = None) -> tuple[int, dict]:
    """
    Exercise main() end-to-end.

    Returns (exit_code, parsed_stdout_json).
    Raises AssertionError if stdout is not valid JSON.
    """
    stdout_buf = io.StringIO()
    stdin_buf = io.StringIO(json.dumps(stdin_json))

    exit_code = 0

    def _fake_run(*args, **kwargs):
        if subprocess_side_effect:
            return subprocess_side_effect(*args, **kwargs)
        return _make_subprocess_result()

    def _fake_connect(path):
        pass

    # Build a fake socket that returns the given response JSON
    fake_sock = MagicMock()
    if socket_response is not None:
        fake_sock.recv.return_value = (json.dumps(socket_response) + "\n").encode()
    else:
        fake_sock.recv.return_value = b""

    with (
        patch("subprocess.run", side_effect=_fake_run),
        patch("socket.socket", return_value=fake_sock),
        patch("sys.stdin", stdin_buf),
        patch("sys.stdout", stdout_buf),
    ):
        try:
            ca.main()
        except SystemExit as exc:
            exit_code = int(exc.code) if exc.code is not None else 0

    output = stdout_buf.getvalue().strip()
    if output:
        return exit_code, json.loads(output)
    return exit_code, {}


# ═════════════════════════════════════════════════════════════════════════════
# Tests: Presence Detection
# ═════════════════════════════════════════════════════════════════════════════

class TestGetIdleTime(unittest.TestCase):

    def _run_with_ioreg(self, idle_ns: int) -> float:
        result = _make_subprocess_result(stdout=_ioreg_output(idle_ns))
        with patch("subprocess.run", return_value=result):
            return ca._get_idle_time_seconds()

    def test_zero_idle(self):
        self.assertAlmostEqual(self._run_with_ioreg(0), 0.0)

    def test_thirty_seconds(self):
        self.assertAlmostEqual(self._run_with_ioreg(30_000_000_000), 30.0, places=1)

    def test_two_minutes(self):
        self.assertAlmostEqual(self._run_with_ioreg(120_000_000_000), 120.0, places=1)

    def test_subprocess_failure_returns_zero(self):
        with patch("subprocess.run", side_effect=Exception("boom")):
            self.assertEqual(ca._get_idle_time_seconds(), 0.0)

    def test_missing_hididletime_returns_zero(self):
        result = _make_subprocess_result(stdout="no idle time here\n")
        with patch("subprocess.run", return_value=result):
            self.assertEqual(ca._get_idle_time_seconds(), 0.0)


class TestIsScreenLocked(unittest.TestCase):

    def _run_with_output(self, stdout: str) -> bool:
        result = _make_subprocess_result(stdout=stdout)
        with patch("subprocess.run", return_value=result):
            return ca._is_screen_locked()

    def test_locked(self):
        self.assertTrue(self._run_with_output("1\n"))

    def test_unlocked(self):
        self.assertFalse(self._run_with_output("0\n"))

    def test_empty_output_returns_false(self):
        self.assertFalse(self._run_with_output(""))

    def test_subprocess_failure_returns_false(self):
        with patch("subprocess.run", side_effect=Exception("boom")):
            self.assertFalse(ca._is_screen_locked())


class TestIsAtDesk(unittest.TestCase):

    def test_at_desk_when_not_locked_and_recent_activity(self):
        with (
            patch.object(ca, "_is_screen_locked", return_value=False),
            patch.object(ca, "_get_idle_time_seconds", return_value=5.0),
        ):
            self.assertTrue(ca.is_at_desk())

    def test_away_when_screen_locked(self):
        with patch.object(ca, "_is_screen_locked", return_value=True):
            self.assertFalse(ca.is_at_desk())

    def test_away_when_idle_exceeds_threshold(self):
        with (
            patch.object(ca, "_is_screen_locked", return_value=False),
            patch.object(ca, "_get_idle_time_seconds", return_value=200.0),
        ):
            self.assertFalse(ca.is_at_desk())

    def test_boundary_exactly_at_threshold_is_away(self):
        # idle == threshold → NOT at desk (strict less-than)
        with (
            patch.object(ca, "_is_screen_locked", return_value=False),
            patch.object(ca, "_get_idle_time_seconds",
                         return_value=float(ca.IDLE_THRESHOLD_SECS)),
        ):
            self.assertFalse(ca.is_at_desk())

    def test_boundary_just_under_threshold_is_at_desk(self):
        with (
            patch.object(ca, "_is_screen_locked", return_value=False),
            patch.object(ca, "_get_idle_time_seconds",
                         return_value=float(ca.IDLE_THRESHOLD_SECS) - 1),
        ):
            self.assertTrue(ca.is_at_desk())


# ═════════════════════════════════════════════════════════════════════════════
# Tests: Local Dialog
# ═════════════════════════════════════════════════════════════════════════════

class TestShowLocalDialog(unittest.TestCase):

    def _run_dialog(self, osascript_stdout: str, returncode: int = 0) -> str:
        result = _make_subprocess_result(stdout=osascript_stdout, returncode=returncode)
        with patch("subprocess.run", return_value=result) as mock_run:
            out = ca.show_local_dialog("Bash", '{"command":"echo hi"}')
        # Verify osascript was called
        mock_run.assert_called_once()
        args = mock_run.call_args[0][0]  # first positional arg = command list
        self.assertEqual(args[0], "/usr/bin/osascript")
        return out

    def test_approve(self):
        self.assertEqual(self._run_dialog("approve\n"), "approve")

    def test_deny(self):
        self.assertEqual(self._run_dialog("deny\n"), "deny")

    def test_timeout(self):
        self.assertEqual(self._run_dialog("timeout\n"), "timeout")

    def test_empty_output_is_timeout(self):
        self.assertEqual(self._run_dialog(""), "timeout")

    def test_unexpected_output_is_timeout(self):
        self.assertEqual(self._run_dialog("something_weird"), "timeout")

    def test_subprocess_exception_is_timeout(self):
        with patch("subprocess.run", side_effect=Exception("osascript not found")):
            result = ca.show_local_dialog("Bash", '{"command":"ls"}')
        self.assertEqual(result, "timeout")

    def test_subprocess_timeout_is_timeout(self):
        import subprocess
        with patch("subprocess.run", side_effect=subprocess.TimeoutExpired(cmd=[], timeout=30)):
            result = ca.show_local_dialog("Bash", '{"command":"ls"}')
        self.assertEqual(result, "timeout")

    def test_script_includes_tool_name(self):
        result = _make_subprocess_result(stdout="approve\n")
        with patch("subprocess.run", return_value=result) as mock_run:
            ca.show_local_dialog("MySpecialTool", '{"key":"val"}')
        script = mock_run.call_args[0][0][-1]  # last arg = the -e script body
        self.assertIn("MySpecialTool", script)

    def test_bash_command_extracted_in_dialog(self):
        result = _make_subprocess_result(stdout="approve\n")
        with patch("subprocess.run", return_value=result) as mock_run:
            ca.show_local_dialog("Bash", '{"command":"rm -rf /danger"}')
        script = mock_run.call_args[0][0][-1]
        self.assertIn("rm -rf /danger", script)

    def test_script_escapes_double_quotes(self):
        result = _make_subprocess_result(stdout="approve\n")
        with patch("subprocess.run", return_value=result) as mock_run:
            ca.show_local_dialog("Bash", '{"command":"echo \\"hi\\""}')
        script = mock_run.call_args[0][0][-1]
        # The raw " should be escaped in the AppleScript string
        self.assertNotIn('echo "hi"', script)


# ═════════════════════════════════════════════════════════════════════════════
# Tests: Mac App Socket Communication
# ═════════════════════════════════════════════════════════════════════════════

class TestSendToMacApp(unittest.TestCase):

    def _make_sock(self, response_bytes: bytes) -> MagicMock:
        sock = MagicMock()
        sock.recv.return_value = response_bytes
        return sock

    def test_returns_decision_on_success(self):
        response = {"id": "abc", "decision": "allow"}
        sock = self._make_sock((json.dumps(response) + "\n").encode())
        with patch("socket.socket", return_value=sock):
            result = ca.send_to_mac_app({"id": "abc", "tool_name": "Bash", "tool_input": "{}"})
        self.assertIsNotNone(result)
        self.assertEqual(result["decision"], "allow")

    def test_payload_sent_as_json_newline(self):
        sock = self._make_sock(b'{"decision":"allow"}\n')
        with patch("socket.socket", return_value=sock):
            ca.send_to_mac_app({"id": "x", "tool_name": "Bash", "tool_input": "{}"})
        sent = b"".join(
            call_args[0][0]
            for call_args in sock.sendall.call_args_list
        )
        payload = json.loads(sent.strip())
        self.assertEqual(payload["tool_name"], "Bash")

    def test_returns_none_on_connection_refused(self):
        sock = MagicMock()
        sock.connect.side_effect = ConnectionRefusedError("no socket")
        with patch("socket.socket", return_value=sock):
            result = ca.send_to_mac_app({"id": "x", "tool_name": "Bash", "tool_input": "{}"})
        self.assertIsNone(result)

    def test_returns_none_on_malformed_response(self):
        sock = self._make_sock(b"not json\n")
        with patch("socket.socket", return_value=sock):
            result = ca.send_to_mac_app({"id": "x", "tool_name": "Bash", "tool_input": "{}"})
        self.assertIsNone(result)

    def test_returns_none_on_empty_response(self):
        sock = self._make_sock(b"")
        with patch("socket.socket", return_value=sock):
            result = ca.send_to_mac_app({"id": "x", "tool_name": "Bash", "tool_input": "{}"})
        self.assertIsNone(result)

    def test_socket_path_is_configured_constant(self):
        self.assertEqual(ca.SOCKET_PATH, "/tmp/claude-remote.sock")


# ═════════════════════════════════════════════════════════════════════════════
# Tests: main() end-to-end
# ═════════════════════════════════════════════════════════════════════════════

class TestMain(unittest.TestCase):

    # ── Hook output format ───────────────────────────────────────────────────

    def test_approve_outputs_allow_hookspecificoutput(self):
        with (
            patch.object(ca, "is_at_desk", return_value=True),
            patch.object(ca, "show_local_dialog", return_value="approve"),
        ):
            exit_code, output = _run_main({"tool_name": "Bash", "tool_input": {"command": "ls"}})
        self.assertEqual(exit_code, 0)
        self.assertEqual(output.get("hookSpecificOutput"), "allow")

    def test_deny_outputs_deny_hookspecificoutput_and_exits_2(self):
        with (
            patch.object(ca, "is_at_desk", return_value=True),
            patch.object(ca, "show_local_dialog", return_value="deny"),
        ):
            exit_code, output = _run_main({"tool_name": "Bash", "tool_input": {"command": "rm"}})
        self.assertEqual(exit_code, 2)
        self.assertEqual(output.get("hookSpecificOutput"), "deny")

    # ── At-desk path ─────────────────────────────────────────────────────────

    def test_at_desk_approve_never_calls_socket(self):
        with (
            patch.object(ca, "is_at_desk", return_value=True),
            patch.object(ca, "show_local_dialog", return_value="approve"),
            patch.object(ca, "send_to_mac_app") as mock_send,
        ):
            _run_main({"tool_name": "Bash", "tool_input": {}})
        mock_send.assert_not_called()

    def test_at_desk_deny_never_calls_socket(self):
        with (
            patch.object(ca, "is_at_desk", return_value=True),
            patch.object(ca, "show_local_dialog", return_value="deny"),
            patch.object(ca, "send_to_mac_app") as mock_send,
        ):
            _run_main({"tool_name": "Bash", "tool_input": {}})
        mock_send.assert_not_called()

    # ── Dialog timeout escalation ────────────────────────────────────────────

    def test_at_desk_dialog_timeout_escalates_to_socket(self):
        with (
            patch.object(ca, "is_at_desk", return_value=True),
            patch.object(ca, "show_local_dialog", return_value="timeout"),
            patch.object(ca, "send_to_mac_app",
                         return_value={"decision": "allow"}) as mock_send,
        ):
            exit_code, output = _run_main({"tool_name": "Bash", "tool_input": {}})
        mock_send.assert_called_once()
        self.assertEqual(exit_code, 0)
        self.assertEqual(output.get("hookSpecificOutput"), "allow")

    def test_at_desk_dialog_timeout_deny_via_socket(self):
        with (
            patch.object(ca, "is_at_desk", return_value=True),
            patch.object(ca, "show_local_dialog", return_value="timeout"),
            patch.object(ca, "send_to_mac_app",
                         return_value={"decision": "deny"}),
        ):
            exit_code, output = _run_main({"tool_name": "Bash", "tool_input": {}})
        self.assertEqual(exit_code, 2)
        self.assertEqual(output.get("hookSpecificOutput"), "deny")

    # ── Away path ────────────────────────────────────────────────────────────

    def test_away_skips_dialog_goes_to_socket(self):
        with (
            patch.object(ca, "is_at_desk", return_value=False),
            patch.object(ca, "show_local_dialog") as mock_dialog,
            patch.object(ca, "send_to_mac_app",
                         return_value={"decision": "allow"}),
        ):
            exit_code, output = _run_main({"tool_name": "Bash", "tool_input": {}})
        mock_dialog.assert_not_called()
        self.assertEqual(exit_code, 0)

    def test_away_socket_deny(self):
        with (
            patch.object(ca, "is_at_desk", return_value=False),
            patch.object(ca, "send_to_mac_app",
                         return_value={"decision": "deny"}),
        ):
            exit_code, output = _run_main({"tool_name": "Bash", "tool_input": {}})
        self.assertEqual(exit_code, 2)

    # ── Fallback: away + socket unavailable ──────────────────────────────────

    def test_away_socket_unavailable_falls_back_to_dialog_approve(self):
        with (
            patch.object(ca, "is_at_desk", return_value=False),
            patch.object(ca, "send_to_mac_app", return_value=None),
            patch.object(ca, "show_local_dialog", return_value="approve"),
        ):
            exit_code, output = _run_main({"tool_name": "Bash", "tool_input": {}})
        self.assertEqual(exit_code, 0)
        self.assertEqual(output.get("hookSpecificOutput"), "allow")

    def test_away_socket_unavailable_dialog_timeout_denies(self):
        """When away, socket unavailable, AND dialog times out → deny (safe default)."""
        with (
            patch.object(ca, "is_at_desk", return_value=False),
            patch.object(ca, "send_to_mac_app", return_value=None),
            patch.object(ca, "show_local_dialog", return_value="timeout"),
        ):
            exit_code, output = _run_main({"tool_name": "Bash", "tool_input": {}})
        self.assertEqual(exit_code, 2)
        self.assertEqual(output.get("hookSpecificOutput"), "deny")

    # ── At desk, socket unavailable ──────────────────────────────────────────

    def test_at_desk_dialog_timeout_socket_unavailable_denies(self):
        """At desk, dialog timed out, and Mac app unavailable → deny."""
        with (
            patch.object(ca, "is_at_desk", return_value=True),
            patch.object(ca, "show_local_dialog", return_value="timeout"),
            patch.object(ca, "send_to_mac_app", return_value=None),
        ):
            exit_code, output = _run_main({"tool_name": "Bash", "tool_input": {}})
        self.assertEqual(exit_code, 2)

    # ── Invalid stdin ────────────────────────────────────────────────────────

    def test_invalid_json_stdin_exits_0_without_output(self):
        """Unparseable hook input → silently exit 0 (don't block Claude)."""
        stdout_buf = io.StringIO()
        with (
            patch("sys.stdin", io.StringIO("NOT JSON {")),
            patch("sys.stdout", stdout_buf),
        ):
            try:
                ca.main()
                exit_code = 0
            except SystemExit as exc:
                exit_code = int(exc.code) if exc.code is not None else 0

        self.assertEqual(exit_code, 0)
        self.assertEqual(stdout_buf.getvalue().strip(), "")

    def test_empty_stdin_exits_0(self):
        stdout_buf = io.StringIO()
        with (
            patch("sys.stdin", io.StringIO("")),
            patch("sys.stdout", stdout_buf),
        ):
            try:
                ca.main()
                exit_code = 0
            except SystemExit as exc:
                exit_code = int(exc.code) if exc.code is not None else 0
        self.assertEqual(exit_code, 0)

    # ── Request includes generated UUID ─────────────────────────────────────

    def test_request_id_sent_to_socket_is_uuid(self):
        import re
        UUID_RE = re.compile(
            r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
        )
        captured = {}

        def _capture(req):
            captured["req"] = req
            return {"decision": "allow"}

        with (
            patch.object(ca, "is_at_desk", return_value=False),
            patch.object(ca, "send_to_mac_app", side_effect=_capture),
        ):
            _run_main({"tool_name": "Bash", "tool_input": {}})

        self.assertIn("req", captured)
        self.assertRegex(captured["req"]["id"], UUID_RE)

    # ── tool_input dict is JSON-encoded before sending ──────────────────────

    def test_dict_tool_input_is_json_encoded_for_socket(self):
        captured = {}

        def _capture(req):
            captured["req"] = req
            return {"decision": "allow"}

        with (
            patch.object(ca, "is_at_desk", return_value=False),
            patch.object(ca, "send_to_mac_app", side_effect=_capture),
        ):
            _run_main({"tool_name": "Bash", "tool_input": {"command": "ls"}})

        tool_input = captured["req"]["tool_input"]
        # It should be a JSON string, not a raw dict
        self.assertIsInstance(tool_input, str)
        parsed = json.loads(tool_input)
        self.assertEqual(parsed["command"], "ls")


# ═════════════════════════════════════════════════════════════════════════════
# Tests: Configuration constants
# ═════════════════════════════════════════════════════════════════════════════

class TestConstants(unittest.TestCase):

    def test_local_timeout_is_positive(self):
        self.assertGreater(ca.LOCAL_TIMEOUT_SECS, 0)

    def test_idle_threshold_is_positive(self):
        self.assertGreater(ca.IDLE_THRESHOLD_SECS, 0)

    def test_remote_timeout_greater_than_local(self):
        self.assertGreater(ca.REMOTE_TIMEOUT_SECS, ca.LOCAL_TIMEOUT_SECS)


if __name__ == "__main__":
    unittest.main()
