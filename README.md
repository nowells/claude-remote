# ClaudeRemote

Native Mac + iOS app for approving Claude Code permission requests via Apple push notifications — no external service required.

Inspired by [claude-push](https://github.com/coa00/claude-push) but built entirely on Apple infrastructure (CloudKit, APNs, IOKit).

---

## How it works

```
Claude Code needs permission
        │
        ▼
claude-approve (hook script)
        │
        ├── At desk? → macOS alert dialog (30 s)
        │                  └─ Approve / Deny → done
        │
        └── Away or timed out → ClaudeRemote Mac app (Unix socket)
                                        │
                                        ▼
                                   CloudKit (iCloud)
                                        │
                                        ▼
                              iPhone / Apple Watch
                              ┌─────────────────┐
                              │ Approve ✓  Deny ✗│  ← lock screen / watch face
                              └─────────────────┘
                                        │
                                        ▼
                                 Decision → Mac → hook → Claude Code
```

**When you're at your desk** the hook shows a native macOS alert dialog.
If you don't respond within 30 seconds (or your screen is locked), the request is
forwarded to your iPhone and Apple Watch as an actionable notification.

No servers. No third-party services. Everything flows through your own iCloud account.

---

## Features

- **At-desk detection** — IOKit idle time + CoreGraphics screen lock state
- **Native macOS dialog** — `osascript` alert with Approve/Deny, 30 s timeout
- **iOS notification actions** — Approve/Deny buttons work from lock screen and Apple Watch
- **CloudKit sync** — uses iCloud private database; nobody else can see your requests
- **In-app UI** — browse and respond to pending requests from within the iOS app
- **Menu bar indicator** — shows number of active requests; settings panel
- **Auto-cleanup** — stale CloudKit records pruned on startup

---

## Requirements

- macOS 13 Ventura+ (Mac app)
- iOS 16+ (iPhone app)
- Xcode 15+ (to build)
- Apple Developer account (free tier works; no paid subscription needed)
- Same Apple ID signed in on both devices

---

## Quick Start

1. Follow **[SETUP.md](SETUP.md)** to build and sign the Xcode project
2. Run `bash scripts/install.sh` to register the hook with Claude Code
3. Start a Claude Code session

---

## Project Structure

```
ClaudeRemote/
├── scripts/
│   ├── claude-approve.py      Hook script called by Claude Code
│   └── install.sh             Registers the hook with Claude Code
├── Sources/
│   ├── Shared/
│   │   └── ApprovalRequest.swift    Shared model (Mac + iOS)
│   ├── MacApp/
│   │   ├── Config.swift             Edit container ID here
│   │   ├── ClaudeRemoteMacApp.swift
│   │   ├── ApprovalCoordinator.swift
│   │   ├── Services/
│   │   │   ├── UnixSocketServer.swift
│   │   │   ├── PresenceDetector.swift
│   │   │   ├── MacCloudKitService.swift
│   │   │   └── MacNotificationService.swift
│   │   ├── Views/
│   │   │   └── MenuBarView.swift
│   │   ├── MacApp.entitlements
│   │   └── Info.plist
│   └── iOSApp/
│       ├── ClaudeRemoteApp.swift
│       ├── iOSApprovalStore.swift
│       ├── Services/
│       │   ├── iOSCloudKitService.swift
│       │   └── iOSNotificationService.swift
│       ├── Views/
│       │   ├── ContentView.swift
│       │   └── ApprovalDetailView.swift
│       ├── iOSApp.entitlements
│       └── Info.plist
└── SETUP.md                   Detailed Xcode setup instructions
```

---

## Comparison with claude-push

| | ClaudeRemote | claude-push |
|---|---|---|
| Notification delivery | CloudKit → APNs (via subscription) | ntfy.sh (external) |
| Response path | CloudKit record update | ntfy.sh HTTP POST |
| Privacy | Stays within your iCloud account | Passes through ntfy.sh servers |
| At-desk shortcut | Native macOS dialog | — |
| Apple Watch support | ✓ (`.timeSensitive` notifications) | depends on ntfy app |
| Setup complexity | Xcode project + Apple ID | Single bash script + ntfy topic |

---

## License

MIT
