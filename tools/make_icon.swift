import AppKit

// Draws the app icon (a glowing green battery with a bolt on a dark rounded square) and writes an .iconset folder.
func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s / 1024, y: s / 1024)

    // macOS icon grid: 824 square centred in 1024
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.45); shadow.shadowBlurRadius = 28; shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    NSColor.black.setFill(); tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    tilePath.addClip()
    NSGradient(colors: [NSColor(red: 0.06, green: 0.12, blue: 0.09, alpha: 1), NSColor(red: 0.01, green: 0.03, blue: 0.02, alpha: 1)])!
        .draw(in: tile, angle: -90)
    // soft green glow behind the battery
    NSGradient(colors: [NSColor(red: 0.20, green: 0.85, blue: 0.40, alpha: 0.38), NSColor(red: 0.20, green: 0.85, blue: 0.40, alpha: 0)])!
        .draw(fromCenter: NSPoint(x: 512, y: 520), radius: 0, toCenter: NSPoint(x: 512, y: 520), radius: 470, options: [])

    // battery body
    let body = NSRect(x: 226, y: 372, width: 520, height: 280)
    let outline = NSBezierPath(roundedRect: body, xRadius: 78, yRadius: 78)
    outline.lineWidth = 26
    NSColor.white.withAlphaComponent(0.88).setStroke(); outline.stroke()
    // nub
    let nub = NSBezierPath(roundedRect: NSRect(x: 764, y: 462, width: 44, height: 100), xRadius: 20, yRadius: 20)
    NSColor.white.withAlphaComponent(0.88).setFill(); nub.fill()
    // charge fill
    let fill = NSRect(x: 256, y: 402, width: 460, height: 220)
    let fillPath = NSBezierPath(roundedRect: fill, xRadius: 52, yRadius: 52)
    NSGradient(colors: [NSColor(red: 0.45, green: 0.97, blue: 0.55, alpha: 1), NSColor(red: 0.13, green: 0.74, blue: 0.33, alpha: 1)])!.draw(in: fillPath, angle: -90)
    // bolt
    let bolt = NSBezierPath()
    bolt.move(to: NSPoint(x: 548, y: 650)); bolt.line(to: NSPoint(x: 400, y: 478)); bolt.line(to: NSPoint(x: 492, y: 478))
    bolt.line(to: NSPoint(x: 452, y: 372 + 8)); bolt.line(to: NSPoint(x: 624, y: 556)); bolt.line(to: NSPoint(x: 526, y: 556)); bolt.close()
    NSGraphicsContext.saveGraphicsState()
    let bs = NSShadow(); bs.shadowColor = NSColor.black.withAlphaComponent(0.35); bs.shadowBlurRadius = 14; bs.shadowOffset = NSSize(width: 0, height: -6); bs.set()
    NSColor.white.setFill(); bolt.fill()
    NSGraphicsContext.restoreGraphicsState()

    // top highlight
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.10), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: 100, y: 512, width: 824, height: 412), angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256),
                   ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
}
