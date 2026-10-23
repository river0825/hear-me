import AppKit

func squircle(in r: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let c = ctx.cgContext
    let s = size / 1024.0
    c.scaleBy(x: s, y: s)

    // macOS icon: ~10% margin, continuous rounded square
    let inset: CGFloat = 100
    let bg = CGRect(x: inset, y: inset, width: 1024 - 2 * inset, height: 1024 - 2 * inset)
    let path = squircle(in: bg, radius: 185)

    // shadow
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -12), blur: 40, color: CGColor(gray: 0, alpha: 0.35))
    c.addPath(path); c.setFillColor(CGColor(gray: 0.1, alpha: 1)); c.fillPath()
    c.restoreGState()

    // background gradient: deep indigo → teal
    c.saveGState()
    c.addPath(path); c.clip()
    let colors = [CGColor(red: 0.10, green: 0.16, blue: 0.42, alpha: 1),
                  CGColor(red: 0.07, green: 0.45, blue: 0.62, alpha: 1)] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    c.drawLinearGradient(grad, start: CGPoint(x: bg.minX, y: bg.maxY), end: CGPoint(x: bg.maxX, y: bg.minY), options: [])
    // subtle top highlight
    let hl = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [CGColor(gray: 1, alpha: 0.18), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(hl, start: CGPoint(x: bg.midX, y: bg.maxY), end: CGPoint(x: bg.midX, y: bg.midY), options: [])
    c.restoreGState()

    // microphone (left of center)
    let white = CGColor(gray: 1, alpha: 1)
    c.setFillColor(white); c.setStrokeColor(white)
    let micX: CGFloat = 400, micTop: CGFloat = 720, micBottom: CGFloat = 470, micW: CGFloat = 150
    let capsule = CGRect(x: micX - micW / 2, y: micBottom, width: micW, height: micTop - micBottom)
    c.addPath(CGPath(roundedRect: capsule, cornerWidth: micW / 2, cornerHeight: micW / 2, transform: nil)); c.fillPath()
    // cradle arc
    c.setLineWidth(44); c.setLineCap(.round)
    let cr: CGFloat = 135
    c.addArc(center: CGPoint(x: micX, y: 500), radius: cr, startAngle: .pi, endAngle: 0, clockwise: false)
    c.strokePath()
    // stem + base
    c.move(to: CGPoint(x: micX, y: 500 - cr)); c.addLine(to: CGPoint(x: micX, y: 290)); c.strokePath()
    c.move(to: CGPoint(x: micX - 110, y: 290)); c.addLine(to: CGPoint(x: micX + 110, y: 290)); c.strokePath()

    // sound → text: three lines that start as short wave ticks and end as text lines
    c.setLineWidth(44)
    let lines: [(y: CGFloat, x0: CGFloat, x1: CGFloat, alpha: CGFloat)] = [
        (640, 610, 760, 0.95),
        (540, 610, 840, 0.95),
        (440, 610, 720, 0.95),
    ]
    for l in lines {
        c.setStrokeColor(CGColor(gray: 1, alpha: l.alpha))
        c.move(to: CGPoint(x: l.x0, y: l.y)); c.addLine(to: CGPoint(x: l.x1, y: l.y)); c.strokePath()
    }
    // wave ticks between mic and lines
    c.setLineWidth(30)
    for (i, h) in [(0, 44.0), (1, 84.0), (2, 44.0)] as [(Int, CGFloat)] {
        let x: CGFloat = 560
        let y: CGFloat = 640 - CGFloat(i) * 100
        c.setStrokeColor(CGColor(gray: 1, alpha: 0.55))
        c.move(to: CGPoint(x: x, y: y - h / 2)); c.addLine(to: CGPoint(x: x, y: y + h / 2)); c.strokePath()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments[1]
try! FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let sizes: [(String, CGFloat)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                                  ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
for (name, px) in sizes {
    let rep = render(size: px)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
try! render(size: 1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/../AppIcon-1024.png"))
print("ok")
