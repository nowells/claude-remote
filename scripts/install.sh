#!/usr/bin/env bash
# ClaudeRemote installer
# ─────────────────────────────────────────────────────────────────────────────
# Installs the claude-approve hook script and registers it with Claude Code.
# Run this AFTER building and running the Mac app at least once.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SRC="$SCRIPT_DIR/claude-approve.py"
HOOK_DEST="$HOME/.local/bin/claude-approve"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

# ── Colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }

echo ""
echo "  ClaudeRemote — hook installer"
echo "  ─────────────────────────────"
echo ""

# ── Checks ───────────────────────────────────────────────────────────────────

if ! command -v python3 &>/dev/null; then
    error "python3 is required but not found."
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)
if [[ $PYTHON_MAJOR -lt 3 ]] || [[ $PYTHON_MAJOR -eq 3 && $PYTHON_MINOR -lt 9 ]]; then
    error "Python 3.9+ required (found $PYTHON_VERSION)."
fi
info "Python $PYTHON_VERSION found"

if [[ ! -f "$HOOK_SRC" ]]; then
    error "Hook script not found at $HOOK_SRC"
fi

# ── Install hook script ───────────────────────────────────────────────────────

mkdir -p "$HOME/.local/bin"
cp "$HOOK_SRC" "$HOOK_DEST"
chmod +x "$HOOK_DEST"
info "Hook installed: $HOOK_DEST"

# ── Register with Claude Code ─────────────────────────────────────────────────

mkdir -p "$(dirname "$CLAUDE_SETTINGS")"

# Determine which tools to hook. Default: tools that can modify the system.
# Adjust this list to your preference.
HOOK_MATCHER="Bash|Write|Edit|Computer|MultiEdit|NotebookEdit"

if [[ -f "$CLAUDE_SETTINGS" ]]; then
    # File exists — merge our hook in using Python (no jq dependency)
    python3 - "$CLAUDE_SETTINGS" "$HOOK_DEST" "$HOOK_MATCHER" << 'EOF'
import sys, json

settings_path = sys.argv[1]
hook_path     = sys.argv[2]
matcher       = sys.argv[3]

with open(settings_path) as f:
    settings = json.load(f)

settings.setdefault("hooks", {})
settings["hooks"].setdefault("PermissionRequest", [])

our_hook = {
    "matcher": matcher,
    "hooks": [
        {
            "type":    "command",
            "command": hook_path,
            "timeout": 340
        }
    ]
}

# Remove any existing ClaudeRemote entry to avoid duplicates
settings["hooks"]["PermissionRequest"] = [
    h for h in settings["hooks"]["PermissionRequest"]
    if not any(
        hh.get("command", "").endswith("claude-approve")
        for hh in h.get("hooks", [])
    )
]
settings["hooks"]["PermissionRequest"].append(our_hook)

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print("merged")
EOF
    info "Merged hook into existing $CLAUDE_SETTINGS"
else
    # Create fresh settings file
    cat > "$CLAUDE_SETTINGS" << EOF
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": "$HOOK_MATCHER",
        "hooks": [
          {
            "type":    "command",
            "command": "$HOOK_DEST",
            "timeout": 340
          }
        ]
      }
    ]
  }
}
EOF
    info "Created $CLAUDE_SETTINGS"
fi

# ── Test connectivity ─────────────────────────────────────────────────────────

echo ""
echo "  Testing Mac app connection…"
if [[ -S "/tmp/claude-remote.sock" ]]; then
    info "Unix socket found — Mac app is running"
else
    warn "Unix socket not found at /tmp/claude-remote.sock"
    warn "Start the ClaudeRemote Mac app before using Claude Code."
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "  Next steps:"
echo "  1. Build and run the ClaudeRemote Mac app (set it to launch at login)"
echo "  2. Build and install the ClaudeRemote iOS app on your iPhone"
echo "  3. Sign in to iCloud on both devices with the same Apple ID"
echo "  4. Open the iOS app once so it registers the CloudKit subscription"
echo "  5. Start a Claude Code session — permission requests will now route"
echo "     through ClaudeRemote."
echo ""
echo "  Hook matcher (edit $CLAUDE_SETTINGS to change):"
echo "    $HOOK_MATCHER"
echo ""
