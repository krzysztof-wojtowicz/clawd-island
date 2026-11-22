// PoseRenderer.swift
// Debug-only offscreen renderer behind `--render-poses <dir>`: writes one GIF per pose for the README (WP-19).

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

    /// Runs when launched with `--render-poses <dir>`; renders everything, then exits the process.
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--render-poses"), flag + 1 < arguments.count else { return }
        let directory = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError.noMetal }
            for state in PetState.allCases {
                for headphones in [false, true] {
                    let name = headphones ? "\(state.rawValue)-headphones" : state.rawValue
                    let scene = Scene(tiles: [Tile(state: state, headphones: headphones)], columns: 1, tileSize: petSize)
                    try scene.write(to: directory.appendingPathComponent("\(name).gif"), duration: loopLength[state] ?? 1, fps: fps, device: device)
                }
            }
            let hero = Scene(
                tiles: PetState.allCases.map { Tile(state: $0, headphones: false) },
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

    private enum RenderError: Error {
        case noMetal, noTexture, noDestination
    }

    private struct Tile {
        let state: PetState
        let headphones: Bool
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
                view.setHeadphones(tile.headphones)
                // The entry poses play their one-shot motion from the first frame.
                if tile.state == .done || tile.state == .needsInput { view.popOut() }
            }
        }

        func write(to url: URL, duration: Double, fps: Double, device: MTLDevice) throws {
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
            // Settle the 0.2 s pose change and the headphone fade, except for the one-shot poses.
            let name = url.lastPathComponent
            let warmup = name.hasPrefix("done") || name.hasPrefix("needsInput") || name == "hero.gif" ? 0 : 0.5
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
            try Self.encode(images, to: url, delay: 1 / fps)
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
