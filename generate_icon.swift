#!/usr/bin/env swift
/// Generates ClaudeRemote app icon: orange-gradient background + robot helper.
/// Run:  swift generate_icon.swift <output-dir>
import AppKit

// ── Drawing helpers ────────────────────────────────────────────────────────────

func rrect(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: cx - w/2, y: cy - h/2, width: w, height: h),
                 xRadius: r, yRadius: r)
}
func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: 2*r, height: 2*r))
}
func fill(_ path: NSBezierPath, _ c: NSColor, _ a: CGFloat = 1) {
    c.withAlphaComponent(a).setFill(); path.fill()
}
func stroke(_ path: NSBezierPath, _ c: NSColor, _ lw: CGFloat, _ a: CGFloat = 1) {
    c.withAlphaComponent(a).setStroke(); path.lineWidth = lw; path.stroke()
}

// ── Icon renderer ──────────────────────────────────────────────────────────────

func generateIcon(size: Int, outputPath: String) {
    let s = CGFloat(size)
    let f = s / 1024          // scale factor — all constants are in 1024-unit space

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("CGContext failed") }

    let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx

    // ── Palette ────────────────────────────────────────────────────────────────
    let robot    = NSColor(red: 0.935, green: 0.945, blue: 0.995, alpha: 1)
    let eyeDark  = NSColor(red: 0.120, green: 0.130, blue: 0.195, alpha: 1)
    let eyeAmber = NSColor(red: 1.000, green: 0.768, blue: 0.212, alpha: 1)
    let antGlow  = NSColor(red: 1.000, green: 0.855, blue: 0.305, alpha: 1)
    let white    = NSColor.white

    // ── Background: orange gradient (darker at bottom, bright at top) ──────────
    let bg = NSGradient(
        colors: [
            NSColor(red: 0.82, green: 0.22, blue: 0.04, alpha: 1),   // bottom
            NSColor(red: 1.00, green: 0.52, blue: 0.18, alpha: 1)    // top
        ],
        atLocations: [0, 1], colorSpace: .deviceRGB
    )!
    bg.draw(in: NSRect(x: 0, y: 0, width: s, height: s), angle: 90)

    let cx = s * 0.5   // horizontal center

    // ── Body ──────────────────────────────────────────────────────────────────
    fill(rrect(cx, 248*f, 320*f, 128*f, 24*f), robot)
    // Body panel (dark screen-like inset)
    fill(rrect(cx, 252*f, 190*f, 52*f, 12*f), eyeDark)
    // Three amber indicator dots on panel
    for i in [-1, 0, 1] as [CGFloat] {
        fill(circle(cx + i * 38*f, 252*f, 8*f), eyeAmber)
    }

    // ── Neck ──────────────────────────────────────────────────────────────────
    fill(rrect(cx, 375*f, 96*f, 48*f, 20*f), robot)

    // ── Ears ──────────────────────────────────────────────────────────────────
    fill(rrect((512 - 262)*f, 520*f, 52*f, 118*f, 16*f), robot)
    fill(rrect((512 + 262)*f, 520*f, 52*f, 118*f, 16*f), robot)
    // Ear bolt details
    fill(circle((512 - 262)*f, 543*f, 9*f), eyeDark, 0.45)
    fill(circle((512 + 262)*f, 543*f, 9*f), eyeDark, 0.45)

    // ── Head ──────────────────────────────────────────────────────────────────
    fill(rrect(cx, 520*f, 428*f, 368*f, 54*f), robot)

    // ── Eyes ──────────────────────────────────────────────────────────────────
    let eyeY     = 545*f
    let eyeOffX  = 114*f
    let eyeW = 118*f, eyeH = 104*f, eyeR = 22*f

    // Eye sockets
    fill(rrect(cx - eyeOffX, eyeY, eyeW, eyeH, eyeR), eyeDark)
    fill(rrect(cx + eyeOffX, eyeY, eyeW, eyeH, eyeR), eyeDark)

    // Amber terminal-cursor pupils
    let pupW = 58*f, pupH = 64*f
    fill(rrect(cx - eyeOffX, eyeY, pupW, pupH, 10*f), eyeAmber)
    fill(rrect(cx + eyeOffX, eyeY, pupW, pupH, 10*f), eyeAmber)

    // Pupil specular highlights
    fill(circle(cx - eyeOffX - 10*f, eyeY + 10*f, 11*f), white, 0.32)
    fill(circle(cx + eyeOffX - 10*f, eyeY + 10*f, 11*f), white, 0.32)

    // ── Smile arc ─────────────────────────────────────────────────────────────
    let smilePath = NSBezierPath()
    smilePath.appendArc(
        withCenter: NSPoint(x: cx, y: 452*f),
        radius: 80*f, startAngle: 200, endAngle: 340
    )
    smilePath.lineCapStyle = .round
    stroke(smilePath, eyeDark, 18*f)

    // ── Antenna stick ─────────────────────────────────────────────────────────
    fill(rrect(cx, 726*f, 15*f, 82*f, 7*f), robot)

    // ── Antenna ball ─────────────────────────────────────────────────────────
    fill(circle(cx, 815*f, 40*f), antGlow)
    // Outer soft glow ring
    let glowPath = NSBezierPath(ovalIn: NSRect(x: cx - 54*f, y: 815*f - 54*f, width: 108*f, height: 108*f))
    glowPath.lineWidth = 10*f
    NSColor(red: 1, green: 0.9, blue: 0.5, alpha: 0.22).setStroke()
    glowPath.stroke()
    // Specular highlight on ball
    fill(circle(cx - 13*f, 826*f, 13*f), white, 0.50)

    NSGraphicsContext.restoreGraphicsState()

    // ── Write PNG ─────────────────────────────────────────────────────────────
    guard let img = ctx.makeImage() else { fatalError("makeImage failed") }
    let rep = NSBitmapImageRep(cgImage: img)
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG failed") }
    do {
        try png.write(to: URL(fileURLWithPath: outputPath))
        print("✓ \(outputPath)  (\(size)×\(size))")
    } catch {
        fatalError("Write failed: \(error)")
    }
}

// ── Entry point ────────────────────────────────────────────────────────────────

let args = CommandLine.arguments
let outDir = args.count > 1 ? args[1] : "."

// macOS needs: 16 32 64 128 256 512 1024
// iOS needs:   1024  (single universal)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let name = size == 1024 ? "AppIcon_1024.png" : "icon_\(size).png"
    generateIcon(size: size, outputPath: "\(outDir)/\(name)")
}
