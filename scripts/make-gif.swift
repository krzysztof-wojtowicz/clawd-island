// make-gif.swift
// Turns a directory of PNG frames into a looping GIF. Frames of different sizes (the island resizes)
// are anchored at the top of a fixed canvas, horizontally by the window's left edge when the file name
// ends in _x<points> (see record-gif.sh), else centred, and composited on a neutral dark background, so
// the transparent glow and peek areas look clean and the GIF does not jump.
// Run: swift scripts/make-gif.swift <framesDir> <out.gif> <delaySeconds> [maxWidthPx] [holdLastSeconds]
import AppKit
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 4, let delay = Double(args[3]) else {
    FileHandle.standardError.write(Data("usage: make-gif.swift <framesDir> <out.gif> <delay> [maxWidth] [holdLast]\n".utf8))
    exit(1)
}
let maxWidth = args.count > 4 ? Int(args[4]) ?? 0 : 0
let holdLast = args.count > 5 ? Double(args[5]) ?? 0 : 0

let names = ((try? FileManager.default.contentsOfDirectory(atPath: args[1])) ?? [])
    .filter { $0.hasSuffix(".png") }.sorted()
let frames = names.compactMap { name -> CGImage? in
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: "\(args[1])/\(name)") as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}
guard !frames.isEmpty else { FileHandle.standardError.write(Data("no frames\n".utf8)); exit(1) }

let retina = Int(NSScreen.main?.backingScaleFactor ?? 2)
/// Left edge in pixels parsed from `frame-001_x635.png`, nil when absent.
let lefts: [Int?] = names.map { name in
    name.dropLast(4).split(separator: "_").last.flatMap { $0.hasPrefix("x") ? Int($0.dropFirst()) : nil }.map { $0 * retina }
}
let originX = lefts.compactMap { $0 }.min() ?? 0
let anchored = lefts.allSatisfy { $0 != nil }
let canvasW = anchored ? zip(frames, lefts).map { $0.width + $1! - originX }.max()! : frames.map(\.width).max()!
let canvasH = frames.map(\.height).max()!
let scale = maxWidth > 0 && canvasW > maxWidth ? Double(maxWidth) / Double(canvasW) : 1
let outW = Int(Double(canvasW) * scale), outH = Int(Double(canvasH) * scale)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { exit(1) }
CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)

for (index, frame) in frames.enumerated() {
    guard let ctx = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
    ctx.interpolationQuality = .high
    ctx.setFillColor(CGColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)) // #1C1C1E
    ctx.fill(CGRect(x: 0, y: 0, width: outW, height: outH))
    let w = Double(frame.width) * scale, h = Double(frame.height) * scale
    // CGContext origin is bottom-left: top-centre anchoring means y = outH - h.
    let x = anchored ? Double(lefts[index]! - originX) * scale : (Double(outW) - w) / 2
    ctx.draw(frame, in: CGRect(x: x, y: Double(outH) - h, width: w, height: h))
    guard let image = ctx.makeImage() else { exit(1) }
    let seconds = delay + (index == frames.count - 1 ? holdLast : 0)
    CGImageDestinationAddImage(dest, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: seconds]] as CFDictionary)
}
guard CGImageDestinationFinalize(dest) else { exit(1) }
print("\(frames.count) frames, \(outW)x\(outH)")
