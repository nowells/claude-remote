# Claude Remote – iOS Approval Notifications for MCP Tools

Get approval notifications on your iPhone/Apple Watch when Claude Desktop wants to use sensitive tools, even when you're away from your Mac.

## Features

- 🔔 **Remote Approval**: Get notifications on iOS when Claude needs permission to run tools
- 💻 **Smart Routing**: Shows local Mac dialog when you're at your desk, iOS notification when away
- ⌚ **Apple Watch Support**: Respond to approvals directly from your wrist
- 🔒 **Secure**: Uses iCloud CloudKit for sync, Unix sockets for local IPC
- 🎯 **Action Buttons**: Approve or deny directly from notification without opening the app

## Architecture

```
Claude Desktop → Python Hook → Mac App (Unix Socket)
                                   ↓
                            [User at desk?]
                                   ↓
                    ┌──────────────┴──────────────┐
                    ↓                             ↓
              Mac Dialog                    CloudKit
              (30s timeout)                      ↓
                                           iOS Notification
                                           (5min timeout)
```

## Setup

### 1. Configure CloudKit

1. Go to [Apple Developer Portal](https://developer.apple.com/account/resources/identifiers/list/cloudContainer)
2. Create a new **iCloud Container** with identifier: `iCloud.com.claude-remote.app` (or your own)
3. Update `Config.swift` with your container ID

### 2. Build the Apps

**Mac App:**
- Open the Xcode project
- Select the Mac target
- Build and run
- A menu bar icon should appear

**iOS App:**
- Select the iOS target (or iOS Simulator)
- Build and run
- Grant notification permissions when prompted

### 3. Install the Hook

```bash
# Make the installer executable
chmod +x install_hook.sh

# Run the installer
./install_hook.sh
```

This installs the hook script to `~/.claude-remote/approval_hook.py`.

### 4. Configure Claude Desktop

Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/Users/yourname/Documents"],
      "approvalHook": "/Users/yourname/.claude-remote/approval_hook.py"
    }
  }
}
```

**Restart Claude Desktop** after making changes.

## Testing

1. **Start the Mac app** – you should see a robot icon in the menu bar
2. **Start the iOS app** (or simulator) – grant notification permissions
3. **Restart Claude Desktop**
4. In Claude, ask: *"Can you create a file called test.txt in my Documents folder?"*

### Expected Behavior

- **If you're active on your Mac** (within 60 seconds):
  - Native Mac alert dialog appears
  - 30 second timeout
  
- **If you're away from your Mac** (>60 seconds idle):
  - iOS notification with Approve/Deny buttons
  - Also appears on Apple Watch
  - 5 minute timeout

## Configuration

Edit `Config.swift` to customize:

- `cloudKitContainerID` – Your iCloud container
- `idleThresholdSeconds` – When to consider Mac "away" (default: 60s)
- `localDialogTimeoutSeconds` – Mac dialog timeout (default: 30s)
- `remoteResponseTimeoutSeconds` – iOS response timeout (default: 300s)

## Troubleshooting

### "Socket not found" error

- Make sure the Mac app is running (check menu bar)
- The app writes its socket location to `/tmp/claude-remote-USERNAME.path`
- Check permissions: `ls -l /tmp/claude-remote-*`

### No iOS notifications

- Verify notification permissions: iOS Settings → Your App → Notifications
- Check iCloud login: Both devices must use the **same Apple ID**
- Verify CloudKit container ID matches in both apps
- Check Console.app for CloudKit errors

### Mac dialog doesn't appear

- The app considers the Mac "away" if idle >60 seconds
- Move your mouse or type to reset the idle timer
- Check `PresenceDetector` logic if issues persist

### Hook not being called

- Verify `approvalHook` path in `claude_desktop_config.json`
- Check hook is executable: `ls -l ~/.claude-remote/approval_hook.py`
- View Claude logs: `tail -f ~/Library/Logs/Claude/mcp*.log`

## Development

### Files Overview

**Mac App:**
- `Config.swift` – Configuration constants
- `UnixSocketServer.swift` – IPC server for hook communication
- `ApprovalCoordinator.swift` – Main logic (local vs remote routing)
- `MacCloudKitService.swift` – CloudKit publishing/polling
- `PresenceDetector.swift` – Detects if user is at desk
- `MenuBarView.swift` – Menu bar UI

**iOS App:**
- `iOSNotificationService.swift` – Notification posting and action handling
- `iOSCloudKitService.swift` – CloudKit subscription and response writing
- `ContentView.swift` – Pending requests UI

**Shared:**
- `ApprovalRequest.swift` – Data model

**Hook:**
- `approval_hook.py` – Python script called by Claude Desktop

### Socket Discovery

The Mac app writes its socket path to `/tmp/claude-remote-USERNAME.path`.
The Python hook reads this file to find the correct socket, even when the Mac app is sandboxed.

## Privacy & Security

- All approval data syncs via **your private iCloud account**
- Socket permissions set to `0700` (owner only)
- Critical alerts can break through Focus modes
- Requires authentication for approval actions
- Auto-denies on timeout (fail-safe)

## License

MIT License – see LICENSE file

## Credits

Built for use with [Claude Desktop](https://claude.ai) and the [Model Context Protocol](https://modelcontextprotocol.io).
