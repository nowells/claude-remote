# ClaudeRemote — Setup Guide

This guide walks you through building and connecting the Mac and iOS apps.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| macOS 13 Ventura+ | For `MenuBarExtra` API |
| iOS 16+ | For `UNNotificationAction` with `.timeSensitive` |
| Xcode 15+ | For Swift 5.9 / async-await support |
| Apple Developer account | Free tier is fine; iCloud container requires no paid subscription |
| Same Apple ID on both devices | So they share the same CloudKit private database |

---

## Step 1 — Create the iCloud Container

1. Sign in to [developer.apple.com](https://developer.apple.com) → **Certificates, IDs & Profiles**
2. Select **Identifiers** → **+** → **iCloud Containers**
3. Description: `ClaudeRemote`
4. Identifier: `iCloud.com.yourname.clauderemote`  (use your actual reverse-domain)
5. **Continue → Register**

> **Important:** Replace every occurrence of `iCloud.com.yourname.clauderemote` in:
> - `Sources/MacApp/Config.swift`
> - `Sources/MacApp/MacApp.entitlements`
> - `Sources/iOSApp/iOSApp.entitlements`

---

## Step 2 — Create the Xcode Project

1. Open Xcode → **File → New → Project**
2. Choose **macOS → App** → Next
3. Product Name: `ClaudeRemote`
4. Bundle Identifier: `com.yourname.clauderemote`
5. Language: Swift, Interface: SwiftUI
6. **Create**

### Add iOS Target

7. **File → New → Target** → **iOS → App**
8. Product Name: `ClaudeRemoteIOS`
9. Bundle Identifier: `com.yourname.clauderemotios`

### Add Source Files

Add the following files to the **macOS target**:
```
Sources/Shared/ApprovalRequest.swift
Sources/MacApp/Config.swift
Sources/MacApp/ClaudeRemoteMacApp.swift
Sources/MacApp/ApprovalCoordinator.swift
Sources/MacApp/Services/UnixSocketServer.swift
Sources/MacApp/Services/PresenceDetector.swift
Sources/MacApp/Services/MacCloudKitService.swift
Sources/MacApp/Services/MacNotificationService.swift
Sources/MacApp/Views/MenuBarView.swift
```

Add the following files to the **iOS target**:
```
Sources/Shared/ApprovalRequest.swift         ← Add to BOTH targets
Sources/iOSApp/ClaudeRemoteApp.swift
Sources/iOSApp/iOSApprovalStore.swift
Sources/iOSApp/Services/iOSCloudKitService.swift
Sources/iOSApp/Services/iOSNotificationService.swift
Sources/iOSApp/Views/ContentView.swift
Sources/iOSApp/Views/ApprovalDetailView.swift
```

---

## Step 3 — Configure Signing & Capabilities

### macOS Target

1. Select the macOS target → **Signing & Capabilities**
2. Team: your Apple ID
3. **+ Capability → iCloud** → check **CloudKit**
4. Under CloudKit Containers: add `iCloud.com.yourname.clauderemote`
5. **+ Capability → App Sandbox** (required for notarisation)
   - Check **Network: Outgoing Connections (Client)**
   - Check **Apple Events** (needed for osascript dialogs)
6. Set **Info.plist** values (or add to target's Info tab):
   - `LSUIElement = YES` (hides Dock icon)
7. Assign `Sources/MacApp/MacApp.entitlements` as the entitlements file

### iOS Target

1. Select the iOS target → **Signing & Capabilities**
2. Team: same Apple ID
3. **+ Capability → iCloud** → check **CloudKit**
4. Under CloudKit Containers: add `iCloud.com.yourname.clauderemote`
5. **+ Capability → Push Notifications**
6. **+ Capability → Background Modes** → check **Remote notifications**
7. Assign `Sources/iOSApp/iOSApp.entitlements` as the entitlements file
8. Merge the `Sources/iOSApp/Info.plist` entries into the target's Info.plist

---

## Step 4 — Build & Install

### Mac App

```bash
# Build from Xcode, then set to launch at login:
# System Settings → General → Login Items → add ClaudeRemote
```

Or open Xcode, select the macOS scheme, **Product → Run**.

### iOS App

1. Connect your iPhone
2. Select the iOS scheme and your device
3. **Product → Run** (this installs it directly)
4. Open the app once — this registers the CloudKit subscription and push notification permission

---

## Step 5 — Install the Hook Script

```bash
cd /path/to/this/repo
bash scripts/install.sh
```

The installer:
- Copies `claude-approve.py` to `~/.local/bin/claude-approve`
- Registers it in `~/.claude/settings.json` as a `PermissionRequest` hook
- Verifies the Mac app socket is reachable

---

## Step 6 — Test End-to-End

### Test 1: At Desk (local dialog)

With the Mac app running:
```bash
echo '{"tool_name":"Bash","tool_input":{"command":"echo hello"}}' | ~/.local/bin/claude-approve
```
You should see a macOS alert dialog. Clicking **Approve** prints `{"hookSpecificOutput": "allow"}`.

### Test 2: Away Path (iOS push)

Lock your screen, then run the same command. The Mac app should:
1. Skip the dialog (screen locked)
2. Write the request to CloudKit
3. Your iPhone shows a notification with Approve/Deny buttons
4. Tapping a button sends the decision back via CloudKit
5. The script prints the decision

### Test 3: Claude Code integration

Start a Claude Code session. When it tries to run a tool matching the hook
matcher (`Bash|Write|Edit|Computer|MultiEdit|NotebookEdit`), the hook fires
automatically.

---

## CloudKit Schema (auto-created on first run)

| Field | Type | Notes |
|---|---|---|
| `toolName` | String | e.g. `"Bash"` |
| `toolInput` | String | JSON-encoded tool parameters |
| `status` | String | `pending` / `approved` / `denied` |
| `createdAt` | Date | When the request was created |
| `respondedAt` | Date | When the user responded (optional) |
| `alternateInput` | String | Modified input (optional, future use) |

The first time you publish a record, CloudKit will create the schema automatically.
You can view it in the **CloudKit Dashboard** at developer.apple.com.

---

## Troubleshooting

| Problem | Solution |
|---|---|
| Dialog doesn't appear | Check that `LSUIElement = YES` is set and that Mac app is running |
| iOS notification not delivered | Check that Background Modes → Remote notifications is on; open iOS app once to register subscription |
| CloudKit errors on first run | Ensure both devices are signed into same Apple ID; check container ID matches in both entitlements |
| Socket not found | Mac app must be running before the hook script is called |
| `osascript` permission error | System Settings → Privacy & Security → Automation → allow Terminal |
| Notification actions missing on Apple Watch | Ensure `interruptionLevel = .timeSensitive` is set (already done in `iOSNotificationService`) |

---

## Architecture Summary

```
Claude Code
    │  PermissionRequest hook (stdin: JSON)
    ▼
claude-approve.py
    ├─ At desk? ──► osascript dialog (30 s) ──► decision ──► stdout
    │               └─ timeout
    └─ Away / timeout ──► Unix socket /tmp/claude-remote.sock
                                 │
                         ClaudeRemote (Mac, menu bar)
                                 │  writes ApprovalRequest record
                                 ▼
                           CloudKit (iCloud private DB)
                                 │  CKQuerySubscription fires silent push
                                 ▼
                         ClaudeRemote (iOS companion)
                                 │  posts local notification
                                 ▼
                         iPhone / Apple Watch
                           [Approve] [Deny]
                                 │  user taps action
                                 ▼
                         iOS app updates CloudKit record (status = approved/denied)
                                 │
                         Mac app polls CloudKit every 2 s
                                 │  sees status change
                                 ▼
                         Unix socket response ──► claude-approve.py ──► stdout
```
