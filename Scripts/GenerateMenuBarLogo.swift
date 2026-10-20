import AppKit
import CoreGraphics
import Foundation
import ImageIO

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: GenerateMenuBarLogo.swift <source-image> <output-pdf>\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let inputData = try? Data(contentsOf: sourceURL),
      let imageSource = CGImageSourceCreateWithData(inputData as CFData, nil),
      let source = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
    fputs("Could not load source logo at \(sourceURL.path)\n", stderr)
    exit(1)
}

// Convert black artwork on white into a white template mark on transparency.
let width = source.width
let height = source.height
let rowBytes = width * 4
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
var sourcePixels = [UInt8](repeating: 0, count: rowBytes * height)
let sourceRendered = sourcePixels.withUnsafeMutableBytes { buffer -> Bool in
    guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: rowBytes, space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else { return false }
    context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
    return true
}
guard sourceRendered else { fputs("Could not rasterize Clippy logo\n", stderr); exit(1) }

var whitePixels = [UInt8](repeating: 0, count: rowBytes * height)
for offset in stride(from: 0, to: sourcePixels.count, by: 4) {
    let sourceAlpha = Int(sourcePixels[offset + 3])
    guard sourceAlpha > 0 else { continue }
    let premultipliedBrightness = Int(max(sourcePixels[offset], max(sourcePixels[offset + 1], sourcePixels[offset + 2])))
    let brightness = min(255, premultipliedBrightness * 255 / sourceAlpha)
    let inkAlpha = 255 - brightness
    let alpha = UInt8(inkAlpha * sourceAlpha / 255)
    whitePixels[offset] = alpha
    whitePixels[offset + 1] = alpha
    whitePixels[offset + 2] = alpha
    whitePixels[offset + 3] = alpha
}

var page = CGRect(x: 0, y: 0, width: width, height: height)
let whiteLogo = whitePixels.withUnsafeMutableBytes { buffer -> CGImage? in
    guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: rowBytes, space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else { return nil }
    return context.makeImage()
}
guard let cgImage = whiteLogo,
      let consumer = CGDataConsumer(url: outputURL as CFURL),
      let pdfContext = CGContext(consumer: consumer, mediaBox: &page, nil) else {
    fputs("Could not create menu bar PDF at \(outputURL.path)\n", stderr)
    exit(1)
}
pdfContext.beginPDFPage(nil)
pdfContext.draw(cgImage, in: page)
pdfContext.endPDFPage()
pdfContext.closePDF()
