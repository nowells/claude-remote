#!/usr/bin/env python3
"""
claude-approve — ClaudeRemote hook script
==========================================
Registered as a Claude Code `PermissionRequest` hook.
Claude Code calls this script when it needs permission to use a tool.

Decision flow
-------------
1. Read the permission-request JSON from stdin.
2. Check if the user is at their Mac (idle time + screen lock via IOKit/CoreGraphics).
3. IF at desk → show a native macOS alert dialog (30 s timeout).
   • User approves/denies → done.
   • Timeout → escalate to step 4.
4. IF away OR dialog timed out → connect to the ClaudeRemote Mac app via Unix socket.
   The Mac app publishes the request to CloudKit; the iOS companion app picks it up,
   shows a notification with Approve/Deny action buttons, and writes the decision back.
5. Output the Claude Code hook response JSON to stdout and exit.

Exit codes
----------
  0 → allow (approved)
  2 → block (denied) — Claude Code reads `hookSpecificOutput` from stdout
  Any other non-zero → error (Claude Code treats as block with generic message)

Requires: Python 3.9+, macOS 12+ (for IOKit idle time path used here)
"""

import json
import os
import socket
import subprocess
import sys
import uuid

# ── Configuration ──────────────────────────────────────────────────────────────

SOCKET_PATH          = "/tmp/claude-remote.sock"
LOCAL_TIMEOUT_SECS   = 30    # seconds to show the local dialog before escalating
IDLE_THRESHOLD_SECS  = 60    # seconds of inactivity before user is "away"
REMOTE_TIMEOUT_SECS  = 300   # max seconds to wait for an iOS response

# ── Presence Detection ─────────────────────────────────────────────────────────

def _get_idle_time_seconds() -> float:
    """Return seconds since last keyboard/mouse event using IOKit HIDIdleTime."""
    try:
        result = subprocess.run(
            ["ioreg", "-c", "IOHIDSystem", "-d", "4"],
            capture_output=True, text=True, timeout=3,
        )
        for line in result.stdout.splitlines():
            if '"HIDIdleTime"' in line:
                # Line format: |       "HIDIdleTime" = 12345678901 (ns)
                parts = line.split("=", 1)
                if len(parts) == 2:
                    raw = parts[1].strip().split()[0]
                    return int(raw) / 1_000_000_000.0
    except Exception:
        pass
    return 0.0


def _is_screen_locked() -> bool:
    """Return True if the screen saver / lock screen is currently active."""
    try:
        # Use Quartz CGSessionCopyCurrentDictionary via Python-ObjC bridge.
        # pyobjc is bundled with macOS system Python via the Quartz framework.
        code = (
            "import Quartz; "
            "d = Quartz.CGSessionCopyCurrentDictionary(); "
            "print(1 if d and d.get('CGSSessionScreenIsLocked') else 0)"
        )
        result = subprocess.run(
            [sys.executable, "-c", code],
            capture_output=True, text=True, timeout=3,
        )
        return result.stdout.strip() == "1"
    except Exception:
        return False


def is_at_desk() -> bool:
    """Return True if the user is likely physically at their Mac."""
    if _is_screen_locked():
        return False
    return _get_idle_time_seconds() < IDLE_THRESHOLD_SECS


# ── Local Dialog (osascript) ───────────────────────────────────────────────────

def show_local_dialog(tool_name: str, tool_input_str: str) -> str:
    """
    Show a blocking macOS alert dialog via osascript.
    Returns "approve", "deny", or "timeout".
    """
    # Build a readable summary
    try:
        obj = json.loads(tool_input_str)
        if tool_name.lower() in ("bash", "computer") and "command" in obj:
            detail = str(obj["command"])
        else:
            items = [f"{k}: {v}" for k, v in obj.items()]
            detail = "\n".join(items[:4])
    except Exception:
        detail = str(tool_input_str)

    if len(detail) > 300:
        detail = detail[:297] + "…"

    # Escape for AppleScript string literal
    def _esc(s: str) -> str:
        return s.replace("\\", "\\\\").replace('"', '\\"')

    script = f"""try
    set dlg to (display alert "Claude Code Permission Request" ¬
        message "Tool: {_esc(tool_name)}\\n\\n{_esc(detail)}" ¬
        as warning ¬
        buttons {{"Deny", "Approve"}} ¬
        default button "Approve" ¬
        giving up after {LOCAL_TIMEOUT_SECS})
    if gave up of dlg is true then
        return "timeout"
    else if button returned of dlg is "Approve" then
        return "approve"
    else
        return "deny"
    end if
on error
    return "timeout"
end try"""

    try:
        result = subprocess.run(
            ["/usr/bin/osascript", "-e", script],
            capture_output=True,
            text=True,
            timeout=LOCAL_TIMEOUT_SECS + 5,
        )
        output = result.stdout.strip()
        if output in ("approve", "deny", "timeout"):
            return output
        return "timeout"
    except subprocess.TimeoutExpired:
        return "timeout"
    except Exception:
        return "timeout"


# ── Unix Socket (ClaudeRemote Mac app) ────────────────────────────────────────

def send_to_mac_app(request: dict) -> dict | None:
    """
    Connect to the ClaudeRemote Mac app via Unix socket, send the request JSON,
    and wait for a response JSON.  Returns the response dict or None on error.
    """
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(REMOTE_TIMEOUT_SECS + 10)
        sock.connect(SOCKET_PATH)

        payload = json.dumps(request).encode() + b"\n"
        sock.sendall(payload)

        # Read until newline
        chunks: list[bytes] = []
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
            if b"\n" in chunk:
                break

        sock.close()
        raw = b"".join(chunks).strip()
        return json.loads(raw)
    except Exception as exc:
        print(f"[claude-approve] Mac app unreachable: {exc}", file=sys.stderr)
        return None


# ── Main ───────────────────────────────────────────────────────────────────────

def main() -> None:
    # ── 1. Read hook input ─────────────────────────────────────────────────────
    try:
        raw = sys.stdin.read()
        hook_input = json.loads(raw)
    except Exception:
        # Cannot parse — let Claude proceed silently
        sys.exit(0)

    tool_name: str = hook_input.get("tool_name", "unknown")
    tool_input      = hook_input.get("tool_input", {})

    if isinstance(tool_input, dict):
        tool_input_str = json.dumps(tool_input)
    else:
        tool_input_str = str(tool_input)

    request_id = str(uuid.uuid4())
    request = {
        "id":         request_id,
        "tool_name":  tool_name,
        "tool_input": tool_input_str,
    }

    # ── 2. Decision logic ──────────────────────────────────────────────────────
    decision: str | None = None

    at_desk = is_at_desk()

    if at_desk:
        # Show local dialog; if user responds within timeout we're done
        result = show_local_dialog(tool_name, tool_input_str)
        if result in ("approve", "deny"):
            decision = result
        # result == "timeout" → fall through to Mac app / push

    if decision is None:
        # Away from desk, or local dialog timed out → send to Mac app for iOS push
        response = send_to_mac_app(request)
        if response:
            raw_decision = response.get("decision", "allow")
            # Mac app returns "allow" / "deny"
            decision = "approve" if raw_decision == "allow" else "deny"
        else:
            # Mac app unavailable — fall back to a local dialog as last resort
            if not at_desk:
                # Screen was locked / user away; try dialog anyway
                result = show_local_dialog(tool_name, tool_input_str)
                decision = result if result in ("approve", "deny") else "deny"
            else:
                # Already tried dialog and it timed out, Mac app also down
                # Default: deny to be safe
                decision = "deny"

    # ── 3. Output Claude Code hook response ────────────────────────────────────
    if decision == "approve":
        print(json.dumps({"hookSpecificOutput": "allow"}))
        sys.exit(0)
    else:
        print(json.dumps({"hookSpecificOutput": "deny"}))
        sys.exit(2)


if __name__ == "__main__":
    main()
