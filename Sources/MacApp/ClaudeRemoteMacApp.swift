import SwiftUI
import UserNotifications

@main
struct ClaudeRemoteMacApp: App {
    @StateObject private var coordinator = ApprovalCoordinator()

    var body: some Scene {
        // Pure menu-bar app — no Dock icon (set LSUIElement = YES in Info.plist)
        MenuBarExtra {
            MenuBarView()
                .environmentObject(coordinator)
        } label: {
            MenuBarLabel()
                .environmentObject(coordinator)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(coordinator)
        }
    }
}

// MARK: - Menu bar badge label

private struct MenuBarLabel: View {
    @EnvironmentObject var coordinator: ApprovalCoordinator

    var body: some View {
        HStack(spacing: 2) {
            Image(nsImage: MenuBarIcon.create(hasActivity: !coordinator.activeRequests.isEmpty))
            
            if !coordinator.activeRequests.isEmpty {
                Text("\(coordinator.activeRequests.count)")
                    .font(.caption2.monospacedDigit())
            }
        }
    }
}
// MARK: - Menu Bar Icon Generator

private enum MenuBarIcon {
    /// Creates a template-style menu bar icon combining code brackets with a robot/approval theme.
    /// The icon adapts to light/dark mode automatically via template rendering.
    static func create(hasActivity: Bool) -> NSImage {
        // Try loading custom menu bar icon first
        if let customIcon = NSImage(named: "MenuBarIcon") {
            let icon = customIcon.copy() as! NSImage
            icon.isTemplate = true
            icon.size = NSSize(width: 18, height: 18)
            return icon
        }
        
        // Fall back to programmatically generated icon
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        
        // Use template color (will adapt to menu bar theme)
        NSColor.black.setFill()
        NSColor.black.setStroke()
        
        // Draw code brackets <> with robot-like appearance
        let path = NSBezierPath()
        
        // Left bracket <
        path.move(to: NSPoint(x: 5, y: 4))
        path.line(to: NSPoint(x: 2, y: 9))
        path.line(to: NSPoint(x: 5, y: 14))
        
        // Right bracket >
        path.move(to: NSPoint(x: 13, y: 4))
        path.line(to: NSPoint(x: 16, y: 9))
        path.line(to: NSPoint(x: 13, y: 14))
        
        // Robot eyes (dots) in the middle
        let eyeSize: CGFloat = 1.5
        let eyeY: CGFloat = 7
        path.append(NSBezierPath(ovalIn: NSRect(x: 7, y: eyeY, width: eyeSize, height: eyeSize)))
        path.append(NSBezierPath(ovalIn: NSRect(x: 10, y: eyeY, width: eyeSize, height: eyeSize)))
        
        // Small mouth/status indicator
        let mouthPath = NSBezierPath()
        mouthPath.move(to: NSPoint(x: 7.5, y: 11))
        if hasActivity {
            // Alert expression (inverted arc)
            mouthPath.curve(to: NSPoint(x: 10.5, y: 11),
                           controlPoint1: NSPoint(x: 8.5, y: 9.5),
                           controlPoint2: NSPoint(x: 9.5, y: 9.5))
        } else {
            // Neutral/happy expression
            mouthPath.curve(to: NSPoint(x: 10.5, y: 11),
                           controlPoint1: NSPoint(x: 8.5, y: 12),
                           controlPoint2: NSPoint(x: 9.5, y: 12))
        }
        path.append(mouthPath)
        
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
        
        context?.restoreGState()
        image.unlockFocus()
        
        image.isTemplate = true
        return image
    }
}

