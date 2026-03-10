#!/usr/bin/env python3
"""
Claude Desktop approval hook for remote iOS notifications.
Connects to the Mac app via Unix socket.
"""
import sys
import json
import socket
import os
import pwd

def get_socket_path():
    """Discover the socket path from the Mac app."""
    username = pwd.getpwuid(os.getuid()).pw_name
    
    # Try the discovery file first
    discovery_file = f"/tmp/claude-remote-{username}.path"
    if os.path.exists(discovery_file):
        try:
            with open(discovery_file, 'r') as f:
                path = f.read().strip()
                if os.path.exists(path):
                    return path
        except Exception as e:
            print(f"Warning: Could not read socket path file: {e}", file=sys.stderr)
    
    # Fall back to the default location
    default_path = f"/tmp/claude-remote-{username}.sock"
    if os.path.exists(default_path):
        return default_path
    
    # Last resort: check old location for backward compatibility
    old_path = os.path.expanduser("~/.claude-remote.sock")
    if os.path.exists(old_path):
        return old_path
    
    raise FileNotFoundError(
        f"Claude Remote app not running. Socket not found.\n"
        f"Checked: {discovery_file}, {default_path}, {old_path}"
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
    # Read MCP tool call from stdin
    input_data = sys.stdin.read()
    
    try:
        tool_call = json.loads(input_data)
        tool_name = tool_call.get("name", "unknown")
        tool_input = tool_call.get("input", {})
        
        # Request approval
        approved = request_approval(tool_name, tool_input)
        
        # Return result
        sys.exit(0 if approved else 1)
        
    except json.JSONDecodeError as e:
        print(f"Invalid JSON input: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Hook error: {e}", file=sys.stderr)
        sys.exit(1)
