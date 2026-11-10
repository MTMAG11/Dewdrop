import AppKit

// Draws the DMG window background: dark panel, a hint line and an arrow from the app to the Applications folder.
// Usage: make_dmg_background <out-dir>   (writes background.png and background@2x.png, 660x400 points)
func render(_ scale: Int) -> Data {
    let w = 660 * scale, h = 400 * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    let rect = NSRect(x: 0, y: 0, width: 660, height: 400)

    NSGradient(colors: [NSColor(red: 0.09, green: 0.12, blue: 0.10, alpha: 1), NSColor(red: 0.02, green: 0.04, blue: 0.03, alpha: 1)])!.draw(in: rect, angle: -90)
    NSGradient(colors: [NSColor(red: 0.20, green: 0.85, blue: 0.40, alpha: 0.20), NSColor(red: 0.20, green: 0.85, blue: 0.40, alpha: 0)])!
        .draw(fromCenter: NSPoint(x: 330, y: 215), radius: 0, toCenter: NSPoint(x: 330, y: 215), radius: 300, options: [])

    // arrow between the two icon slots (app at x=165, Applications at x=495, icons centred at y=190 from the top)
    let y: CGFloat = 400 - 190
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 250, y: y)); arrow.line(to: NSPoint(x: 395, y: y))
    arrow.lineWidth = 5; arrow.lineCapStyle = .round
    arrow.setLineDash([2, 11], count: 2, phase: 0)
    NSColor(red: 0.30, green: 0.85, blue: 0.45, alpha: 0.9).setStroke(); arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 392, y: y + 15)); head.line(to: NSPoint(x: 418, y: y)); head.line(to: NSPoint(x: 392, y: y - 15))
    head.lineWidth = 5; head.lineCapStyle = .round; head.lineJoinStyle = .round
    NSColor(red: 0.30, green: 0.85, blue: 0.45, alpha: 0.95).setStroke(); head.stroke()

    let para = NSMutableParagraphStyle(); para.alignment = .center
    func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, y: CGFloat) {
        NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                      .foregroundColor: NSColor.white.withAlphaComponent(alpha), .paragraphStyle: para])
            .draw(in: NSRect(x: 0, y: y, width: 660, height: size + 8))
    }
    draw("Dewdrop", size: 26, weight: .bold, alpha: 0.95, y: 338)
    draw("Drag Dewdrop to Applications to install", size: 14, weight: .medium, alpha: 0.65, y: 52)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
try! render(1).write(to: URL(fileURLWithPath: dir + "/background.png"))
try! render(2).write(to: URL(fileURLWithPath: dir + "/background@2x.png"))
