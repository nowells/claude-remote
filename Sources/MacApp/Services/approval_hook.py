#!/usr/bin/env python3
"""
Claude Desktop approval hook for remote iOS notifications.
Connects to the Mac app via Unix socket.
"""
import sys
import json
import socket
import os

def get_socket_path():
    """Discover the socket path from the Mac app."""
    home = os.path.expanduser("~")
    # Sandboxed apps write to their container, not the real home directory
    container_home = os.path.join(home, "Library", "Containers", "com.claude-remote.app", "Data")

    search_dirs = [home, container_home]

    # Try discovery files first
    for base_dir in search_dirs:
        discovery_file = os.path.join(base_dir, ".claude-remote.path")
        if os.path.exists(discovery_file):
            try:
                with open(discovery_file, 'r') as f:
                    path = f.read().strip()
                    if os.path.exists(path):
                        return path
            except Exception as e:
                print(f"Warning: Could not read {discovery_file}: {e}", file=sys.stderr)

    # Fall back to direct socket paths
    for base_dir in search_dirs:
        sock_path = os.path.join(base_dir, ".claude-remote.sock")
        if os.path.exists(sock_path):
            return sock_path

    checked = [os.path.join(d, f) for d in search_dirs for f in [".claude-remote.path", ".claude-remote.sock"]]
    raise FileNotFoundError(
        f"Claude Remote app not running. Socket not found.\n"
        f"Checked: {', '.join(checked)}"
    )

TIMEOUT = 310  # Slightly longer than remoteResponseTimeoutSeconds

def request_approval(tool_name, tool_input):
    """Connect to Mac app and request approval."""
    try:
        socket_path = get_socket_path()
        
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(TIMEOUT)
        sock.connect(socket_path)
        
        # Send request
        request = {
            "tool_name": tool_name,
            "tool_input": json.dumps(tool_input)
        }
        sock.sendall((json.dumps(request) + "\n").encode('utf-8'))
        
        # Read response
        response_data = b""
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            response_data += chunk
            if b"\n" in chunk:
                break
        
        sock.close()
        
        # Parse response
        response = json.loads(response_data.decode('utf-8'))
        
        if "error" in response:
            print(f"Error from approval service: {response['error']}", file=sys.stderr)
            return False
        
        return response.get("decision") == "allow"
        
    except socket.timeout:
        print("Approval request timed out", file=sys.stderr)
        return False
    except FileNotFoundError as e:
        print(str(e), file=sys.stderr)
        return False
    except Exception as e:
        print(f"Approval request failed: {e}", file=sys.stderr)
        return False

if __name__ == "__main__":
    # Read PermissionRequest hook input from stdin
    input_data = sys.stdin.read()

    try:
        tool_call = json.loads(input_data)
        tool_name = tool_call.get("tool_name", "unknown")
        tool_input = tool_call.get("tool_input", {})

        # Request approval
        approved = request_approval(tool_name, tool_input)

        # Return PermissionRequest decision as JSON
        result = {
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {
                    "behavior": "allow" if approved else "deny"
                }
            }
        }
        print(json.dumps(result))
        sys.exit(0)

    except json.JSONDecodeError as e:
        print(f"Invalid JSON input: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Hook error: {e}", file=sys.stderr)
        sys.exit(1)
