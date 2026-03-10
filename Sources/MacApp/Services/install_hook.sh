#!/bin/bash

# Claude Remote Approval Hook Installer
# This installs the Python approval hook for Claude Desktop

set -e

HOOK_NAME="approval_hook.py"
INSTALL_DIR="$HOME/.claude-remote"
HOOK_PATH="$INSTALL_DIR/$HOOK_NAME"
CONFIG_PATH="$HOME/.claude/settings.json"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "🤖 Installing Claude Remote approval hook..."

# Create installation directory
mkdir -p "$INSTALL_DIR"

# Copy the hook script from the repo
if [ -f "$SCRIPT_DIR/approval_hook.py" ]; then
    cp "$SCRIPT_DIR/approval_hook.py" "$HOOK_PATH"
    echo "✅ Copied hook script to: $HOOK_PATH"
else
    echo "❌ Error: approval_hook.py not found in $SCRIPT_DIR"
    exit 1
fi

chmod +x "$HOOK_PATH"

echo ""

# Check if config file exists
if [ ! -f "$CONFIG_PATH" ]; then
    echo "⚠️  Claude Code settings not found. Creating new config..."
    mkdir -p "$(dirname "$CONFIG_PATH")"
    cat > "$CONFIG_PATH" << 'CONFIGEOF'
{}
CONFIGEOF
fi

# Add or update the PreToolUse permissions hook using Python for JSON manipulation
python3 - "$CONFIG_PATH" "$HOOK_PATH" << 'PYEOF'
import sys, json

config_path = sys.argv[1]
hook_path = sys.argv[2]

with open(config_path, 'r') as f:
    config = json.load(f)

hook_entry = {"matcher": ".*", "hooks": [{"type": "command", "command": hook_path}]}

hooks = config.setdefault("hooks", {})
pre_tool_use = hooks.setdefault("PermissionRequest", [])

# Replace existing claude-remote entry if present, otherwise append
for i, entry in enumerate(pre_tool_use):
    for h in entry.get("hooks", []):
        if "claude-remote" in h.get("command", ""):
            pre_tool_use[i] = hook_entry
            break
    else:
        continue
    break
else:
    pre_tool_use.append(hook_entry)

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')

print(f"✅ Updated {config_path}")
PYEOF

echo ""
echo "📝 Permissions hook added to:"
echo "   $CONFIG_PATH"
echo ""
echo "Hook configuration:"
echo ""
cat << EXAMPLEEOF
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": ".*",
        "hooks": [{"type": "command", "command": "$HOOK_PATH"}]
      }
    ]
  }
}
EXAMPLEEOF
echo ""
echo "✅ Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Build and run the Claude Remote Mac app"
echo "  2. Build and run the Claude Remote iOS app (or simulator)"
echo "  3. Restart Claude Code (the hook is already configured)"
echo ""
echo "The hook will automatically discover the Mac app's socket location."
echo ""
