// PoseRenderer.swift
// Debug-only offscreen renderer behind `--render-poses <dir> [--pet-style <style>]` (one GIF per pose for the README) and
// `--render-icon <dir>` (the app icon's iconset PNGs).

#if DEBUG
import AppKit
import ClawdCore
import ImageIO
import Metal
import QuartzCore
import UniformTypeIdentifiers

/// Renders `PetView`s into a Metal texture with `CARenderer` at fixed time steps and encodes the frames as looping GIFs.
/// Needs no Screen Recording permission. Release builds do not contain it.
@MainActor
enum PoseRenderer {
    private static let fps = 20.0
    /// Loop length per state in seconds: a whole number of the state's animation periods (docs/07).
    private static let loopLength: [PetState: Double] = [
        .sleeping: 3.2, .idle: 4.5, .thinking: 1.6, .usingTools: 1.4, .compacting: 1, .juggling: 1.2, .talking: 0.9,
        .done: 1.6, .needsInput: 1.6,
    ]
    /// Pet size in pixels: the unit box (32 × 24) at 5 px per unit.
    private static let petSize = CGSize(width: 160, height: 120)
    /// `--pet-style <roundy|sharpy>` renders the poses in that style (REQ-06 AC2); roundy when absent or unknown.
    private static let style: AppConfig.PetStyle = {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--pet-style"), flag + 1 < arguments.count else { return .roundy }
        return AppConfig.PetStyle(rawValue: arguments[flag + 1]) ?? .roundy
    }()

    /// Runs when launched with `--render-poses <dir>`; renders everything, then exits the process.
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--render-icon"), flag + 1 < arguments.count {
            renderIcon(into: URL(fileURLWithPath: arguments[flag + 1], isDirectory: true))
        }
        guard let flag = arguments.firstIndex(of: "--render-poses"), flag + 1 < arguments.count else { return }
        let directory = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError.noMetal }
            for state in PetState.allCases {
                let scene = Scene(tiles: [Tile(state: state)], columns: 1, tileSize: petSize)
                try scene.write(to: directory.appendingPathComponent("\(state.rawValue).gif"), duration: loopLength[state] ?? 1, fps: fps, device: device)
            }
            let hero = Scene(
                tiles: PetState.allCases.map { Tile(state: $0) },
                columns: 3,
                tileSize: CGSize(width: 96, height: 72)
            )
            try hero.write(to: directory.appendingPathComponent("hero.gif"), duration: 3.2, fps: 10, device: device)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("render-poses failed: \(error)\n".utf8))
            exit(1)
        }
    }

    /// Writes `icon_<size>x<size>[@2x].png` for an `.iconset`: the idle pet on a dark rounded square, on Apple's
    /// 824 pt tile inside a 1024 pt canvas. Exits the process.
    private static func renderIcon(into directory: URL) -> Never {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError.noMetal }
            let tile = 824.0
            let scene = Scene(tiles: [Tile(state: .idle)], columns: 1, tileSize: CGSize(width: tile, height: tile))
            scene.root.cornerRadius = tile * 0.2237
            scene.root.masksToBounds = true
            // An idle pose from the middle of its blink cycle, not a half-transitioned first frame.
            let art = try scene.frames(duration: 0.1, fps: 10, warmup: 1, device: device)[0]
            let sizes = [16, 32, 128, 256, 512]
            for size in sizes {
                for scale in [1, 2] {
                    let pixels = size * scale
                    let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
                    try writePNG(art, canvas: 1024, tile: tile, pixels: pixels, to: directory.appendingPathComponent(name))
                }
            }
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("render-icon failed: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func writePNG(_ art: CGImage, canvas: Double, tile: Double, pixels: Int, to url: URL) throws {
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw RenderError.noTexture }
        context.interpolationQuality = .high
        let scale = Double(pixels) / canvas
        let inset = (canvas - tile) / 2 * scale
        context.draw(art, in: CGRect(x: inset, y: inset, width: tile * scale, height: tile * scale))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw RenderError.noDestination }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RenderError.noDestination }
    }

    private enum RenderError: Error {
        case noMetal, noTexture, noDestination
    }

    private struct Tile {
        let state: PetState
    }

    /// A black canvas with a grid of pets, each in its own state.
    @MainActor
    private struct Scene {
        let root = CALayer()
        let views: [PetView]
        let size: CGSize

        init(tiles: [Tile], columns: Int, tileSize: CGSize) {
            let rows = (tiles.count + columns - 1) / columns
            let size = CGSize(width: tileSize.width * CGFloat(columns), height: tileSize.height * CGFloat(rows))
            let root = root
            self.size = size
            root.bounds = CGRect(origin: .zero, size: size)
            root.position = CGPoint(x: size.width / 2, y: size.height / 2)
            root.backgroundColor = PetTokens.islandBackground
            // CARenderer's texture is y-down relative to layer space.
            root.sublayerTransform = CATransform3DMakeScale(1, -1, 1)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            views = tiles.enumerated().map { index, tile in
                let view = PetView(frame: .zero)
                view.setStyle(PoseRenderer.style)
                let column = index % columns
                let row = index / columns
                // A 10 % margin keeps props that stick out of the unit box (hammer, balls) inside the frame.
                view.frame = CGRect(
                    x: CGFloat(column) * tileSize.width,
                    y: size.height - CGFloat(row + 1) * tileSize.height,
                    width: tileSize.width,
                    height: tileSize.height
                ).insetBy(dx: tileSize.width * 0.1, dy: tileSize.height * 0.1)
                view.layout()
                if let layer = view.layer {
                    layer.frame = view.frame
                    root.addSublayer(layer)
                }
                return view
            }
            CATransaction.commit()
            for (view, tile) in zip(views, tiles) {
                view.setState(tile.state)
                // The entry poses play their one-shot motion from the first frame.
                if tile.state == .done || tile.state == .needsInput { view.popOut() }
            }
        }

        func write(to url: URL, duration: Double, fps: Double, device: MTLDevice) throws {
            // Settle the 0.2 s pose change, except for the one-shot poses.
            let name = url.lastPathComponent
            let warmup = name.hasPrefix("done") || name.hasPrefix("needsInput") || name == "hero.gif" ? 0 : 0.5
            try Self.encode(frames(duration: duration, fps: fps, warmup: warmup, device: device), to: url, delay: 1 / fps)
        }

        /// Renders `duration` seconds at `fps` after `warmup` seconds of unrecorded animation.
        func frames(duration: Double, fps: Double, warmup: Double, device: MTLDevice) throws -> [CGImage] {
            let width = Int(size.width), height = Int(size.height)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: descriptor) else { throw RenderError.noTexture }
            let renderer = CARenderer(mtlTexture: texture, options: nil)
            renderer.layer = root
            renderer.bounds = root.bounds

            CATransaction.flush()
            let start = CACurrentMediaTime()
            var images: [CGImage] = []
            let frames = Int((duration * fps).rounded())
            for index in -Int(warmup * fps)..<frames {
                let time = start + Double(index + Int(warmup * fps)) / fps
                renderer.beginFrame(atTime: time, timeStamp: nil)
                renderer.addUpdate(renderer.bounds)
                renderer.render()
                renderer.endFrame()
                // CARenderer submits its GPU work on a queue of its own and offers no completion hook.
                usleep(25_000)
                if index >= 0 { images.append(try Self.image(of: texture, width: width, height: height)) }
            }
            return images
        }

        private static func image(of texture: MTLTexture, width: Int, height: Int) throws -> CGImage {
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            texture.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            guard let context = CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info
            ), let image = context.makeImage() else { throw RenderError.noTexture }
            return image
        }

        private static func encode(_ images: [CGImage], to url: URL, delay: Double) throws {
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, images.count, nil) else {
                throw RenderError.noDestination
            }
            let file = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
            CGImageDestinationSetProperties(destination, file as CFDictionary)
            let frame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]]
            for image in images { CGImageDestinationAddImage(destination, image, frame as CFDictionary) }
            guard CGImageDestinationFinalize(destination) else { throw RenderError.noDestination }
        }
    }
}
#endif
