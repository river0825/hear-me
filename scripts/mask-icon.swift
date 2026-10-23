import AppKit

// Usage: mask-icon <source.png> <out-dir>
// Masks a full-bleed 1024x1024 artwork to the macOS rounded-square icon shape (10% margin, continuous corners),
// adds the standard drop shadow, and writes AppIcon.iconset/*.png + AppIcon-1024.png into <out-dir>.
let args = CommandLine.arguments
guard args.count == 3, let src = NSImage(contentsOfFile: args[1]) else { fputs("usage: mask-icon <source.png> <out-dir>\n", stderr); exit(2) }
let outDir = args[2]
try! FileManager.default.createDirectory(atPath: outDir + "/AppIcon.iconset", withIntermediateDirectories: true)

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
    let inset: CGFloat = 100
    let bg = CGRect(x: inset, y: inset, width: 1024 - 2 * inset, height: 1024 - 2 * inset)
    let path = CGPath(roundedRect: bg, cornerWidth: 185, cornerHeight: 185, transform: nil)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -12), blur: 40, color: CGColor(gray: 0, alpha: 0.35))
    c.addPath(path); c.setFillColor(CGColor(gray: 0.1, alpha: 1)); c.fillPath()
    c.restoreGState()
    c.saveGState()
    c.addPath(path); c.clip()
    // Scale the artwork so its central 80% fills the rounded square (art is full-bleed, we crop the margins).
    let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let scale: CGFloat = 1.0 / 0.84
    let w = bg.width * scale, h = bg.height * scale
    c.interpolationQuality = .high
    c.draw(cg, in: CGRect(x: bg.midX - w / 2, y: bg.midY - h / 2, width: w, height: h))
    c.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let sizes: [(String, CGFloat)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                                  ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
for (name, px) in sizes {
    try! render(size: px).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/AppIcon.iconset/icon_\(name).png"))
}
try! render(size: 1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/AppIcon-1024.png"))
print("ok")
