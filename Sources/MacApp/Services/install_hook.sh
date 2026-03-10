#!/bin/bash

# Claude Remote Approval Hook Installer
# This installs the Python approval hook for Claude Desktop

set -e

HOOK_NAME="approval_hook.py"
INSTALL_DIR="$HOME/.claude-remote"
HOOK_PATH="$INSTALL_DIR/$HOOK_NAME"
CONFIG_PATH="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
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
    echo "⚠️  Claude Desktop config not found. Creating new config..."
    mkdir -p "$(dirname "$CONFIG_PATH")"
    cat > "$CONFIG_PATH" << 'CONFIGEOF'
{
  "mcpServers": {}
}
CONFIGEOF
fi

echo "📝 To enable approval for an MCP server, edit:"
echo "   $CONFIG_PATH"
echo ""
echo "Add 'approvalHook' to any server configuration:"
echo ""
cat << EXAMPLEEOF
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "$HOME/Documents"],
      "approvalHook": "$HOOK_PATH"
    }
  }
}
EXAMPLEEOF
echo ""
echo "✅ Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Build and run the Claude Remote Mac app"
echo "  2. Build and run the Claude Remote iOS app (or simulator)"
echo "  3. Update $CONFIG_PATH as shown above"
echo "  4. Restart Claude Desktop"
echo ""
echo "The hook will automatically discover the Mac app's socket location."
echo ""
