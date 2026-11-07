// Renders Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: the body is 824/1024 of the canvas.
    let inset = s * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = body.width * 0.225
    let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    NSGradient(starting: NSColor(red: 0.13, green: 0.15, blue: 0.22, alpha: 1),
               ending: NSColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1))!.draw(in: shape, angle: -90)

    // Three tiles, 40/30/30 with the right column split, like a Tessera mode.
    let pad = body.width * 0.14
    let gap = body.width * 0.045
    let area = body.insetBy(dx: pad, dy: pad)
    let leftWidth = (area.width - gap) * 0.55
    let rightWidth = area.width - gap - leftWidth
    let tileHeight = (area.height - gap) / 2
    let tiles: [(NSRect, NSColor)] = [
        (NSRect(x: area.minX, y: area.minY, width: leftWidth, height: area.height),
         NSColor(red: 0.30, green: 0.56, blue: 1.00, alpha: 1)),
        (NSRect(x: area.minX + leftWidth + gap, y: area.minY + tileHeight + gap, width: rightWidth, height: tileHeight),
         NSColor(red: 0.98, green: 0.72, blue: 0.30, alpha: 1)),
        (NSRect(x: area.minX + leftWidth + gap, y: area.minY, width: rightWidth, height: tileHeight),
         NSColor(red: 0.36, green: 0.85, blue: 0.66, alpha: 1)),
    ]
    let tileRadius = body.width * 0.06
    for (rect, color) in tiles {
        let tile = NSBezierPath(roundedRect: rect, xRadius: tileRadius, yRadius: tileRadius)
        NSGradient(starting: color.highlight(withLevel: 0.15)!, ending: color)!.draw(in: tile, angle: -90)
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in sizes where size <= 512 {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()
print("Wrote \(output.path)")
