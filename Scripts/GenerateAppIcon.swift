import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: GenerateAppIcon.swift <source-image> <iconset-directory>\n", stderr)
    exit(2)
}

let sourcePath = CommandLine.arguments[1]
let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
guard let logo = NSImage(contentsOfFile: sourcePath) else {
    fputs("Could not load Clippy logo at \(sourcePath)\n", stderr)
    exit(1)
}
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func iconPNG(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.shouldAntialias = true
    context.imageInterpolation = .high

    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    // Keep the source's transparent outer area so its shadow and silhouette
    // remain visible against the macOS Dock and app switcher backgrounds.
    NSColor.clear.setFill()
    bounds.fill()
    let sourceSize = logo.size
    let scale = min(CGFloat(size) / sourceSize.width, CGFloat(size) / sourceSize.height)
    let logoSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
    let logoBounds = CGRect(
        x: (CGFloat(size) - logoSize.width) / 2,
        y: (CGFloat(size) - logoSize.height) / 2,
        width: logoSize.width,
        height: logoSize.height
    )
    logo.draw(in: logoBounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let images: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for (name, size) in images {
    try iconPNG(size: size).write(to: iconsetURL.appendingPathComponent(name), options: .atomic)
}
