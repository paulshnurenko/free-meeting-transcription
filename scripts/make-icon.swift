// Draws the app icon and writes Resources/AppIcon.icns.
//   swift scripts/make-icon.swift
import AppKit

let size: CGFloat = 1024

func draw(in ctx: CGContext) {
    // macOS icon grid: an 824 pt rounded square centred on the 1024 canvas, with a soft shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    ctx.addPath(path)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(red: 0.16, green: 0.18, blue: 0.42, alpha: 1).cgColor,
        NSColor(red: 0.33, green: 0.30, blue: 0.86, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.minY), end: CGPoint(x: 0, y: tile.maxY), options: [])

    // Waveform: rounded bars, symmetric around the centre line.
    let heights: [CGFloat] = [120, 230, 360, 470, 330, 420, 250, 150]
    let barWidth: CGFloat = 46, gap: CGFloat = 30
    let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var x = tile.midX - total / 2
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.95).cgColor)
    for h in heights {
        let bar = CGRect(x: x, y: tile.midY - h / 2 - 20, width: barWidth, height: h)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        ctx.fillPath()
        x += barWidth + gap
    }

    // Record dot.
    let dot = CGRect(x: tile.maxX - 230, y: tile.maxY - 230, width: 120, height: 120)
    ctx.setFillColor(NSColor(red: 1, green: 0.27, blue: 0.27, alpha: 1).cgColor)
    ctx.fillEllipse(in: dot)
    ctx.restoreGState()
}

func png(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: CGFloat(pixels) / size, y: CGFloat(pixels) / size)
    draw(in: ctx)
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(filePath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(base).write(to: iconset.appending(path: "icon_\(base)x\(base).png"))
    try png(base * 2).write(to: iconset.appending(path: "icon_\(base)x\(base)@2x.png"))
}
let output = root.appending(path: "Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(filePath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try png(512).write(to: root.appending(path: "Resources/AppIcon-preview.png"))
print(output.path)
