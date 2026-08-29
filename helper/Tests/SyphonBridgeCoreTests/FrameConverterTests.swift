import XCTest
import CoreImage
import Metal
@testable import SyphonBridgeCore

final class FrameConverterTests: XCTestCase {

    func testConvertProducesExactPixelsAtSourceSize() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal device available")
        }
        // Without scaling, every source pixel must come back bit for bit.
        // This is the whole point of sending raw RGBA.
        let W = 64, H = 32
        var source = [UInt8](repeating: 0, count: W * H * 4)
        var seed: UInt32 = 987654321
        for i in stride(from: 0, to: W * H * 4, by: 4) {
            seed = seed &* 1664525 &+ 1013904223
            source[i]     = UInt8((seed >> 8) & 0xFF)   // B
            source[i + 1] = UInt8((seed >> 16) & 0xFF)  // G
            source[i + 2] = UInt8((seed >> 24) & 0xFF)  // R
            source[i + 3] = 255
        }
        let texture = try makeTextureFromBGRA(device: device, width: W, height: H, bgra: source)

        let converter = FrameConverter(context: CIContext(mtlDevice: device))

        let out = try XCTUnwrap(converter.convert(texture), "conversion failed")
        XCTAssertEqual(out.count, W * H * 4, "wrong RGBA byte count")

        // Output is RGBA, input was BGRA, so compare with the channels swapped.
        var maxError = 0
        out.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            for i in stride(from: 0, to: W * H * 4, by: 4) {
                maxError = max(maxError, abs(Int(p[i])     - Int(source[i + 2]))) // R
                maxError = max(maxError, abs(Int(p[i + 1]) - Int(source[i + 1]))) // G
                maxError = max(maxError, abs(Int(p[i + 2]) - Int(source[i])))     // B
            }
        }
        XCTAssertEqual(maxError, 0, "not lossless: worst error \(maxError)/255")
    }

    func testConvertKeepsSourceResolution() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal device available")
        }
        // No downscaling: the source resolution comes through unchanged.
        let texture = try makeTexture(device: device, width: 1920, height: 1080)
        let converter = FrameConverter(context: CIContext(mtlDevice: device))

        let out = try XCTUnwrap(converter.convert(texture))
        XCTAssertEqual(out.count, 1920 * 1080 * 4, "byte count does not match source resolution")
    }

    func testConvertKeepsAlphaOpaque() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal device available")
        }
        // Treat the preview as opaque even if the source carries alpha.
        // ImageData honours alpha verbatim, so leaving it would let the canvas
        // background show through.
        let W = 8, H = 8
        var source = [UInt8](repeating: 0, count: W * H * 4)
        for i in stride(from: 0, to: W * H * 4, by: 4) {
            source[i] = 10; source[i+1] = 20; source[i+2] = 30
            source[i+3] = 0   // fully transparent
        }
        let texture = try makeTextureFromBGRA(device: device, width: W, height: H, bgra: source)

        let converter = FrameConverter(context: CIContext(mtlDevice: device))

        let out = try XCTUnwrap(converter.convert(texture))
        out.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            for i in stride(from: 0, to: W * H * 4, by: 4) {
                XCTAssertEqual(p[i + 3], 255, "alpha was not forced opaque")
            }
        }
    }

    private func makeTextureFromBGRA(device: MTLDevice, width: Int, height: Int,
                                     bgra: [UInt8]) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        let texture = try XCTUnwrap(device.makeTexture(descriptor: desc))
        bgra.withUnsafeBytes { buf in
            texture.replace(region: MTLRegionMake2D(0, 0, width, height),
                            mipmapLevel: 0, withBytes: buf.baseAddress!, bytesPerRow: width * 4)
        }
        return texture
    }

    /// Builds a texture with a noisy gradient. A flat colour would compress
    /// away any difference, so the noise is deliberate.
    private func makeTexture(device: MTLDevice, width: Int, height: Int) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        let texture = try XCTUnwrap(device.makeTexture(descriptor: desc))

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var seed: UInt32 = 12345
        for y in 0..<height {
            for x in 0..<width {
                seed = seed &* 1664525 &+ 1013904223
                let noise = UInt8((seed >> 16) & 0x3F)
                let i = (y * width + x) * 4
                pixels[i]     = UInt8((x * 255) / width) &+ noise      // B
                pixels[i + 1] = UInt8((y * 255) / height) &+ noise     // G
                pixels[i + 2] = noise &* 3                             // R
                pixels[i + 3] = 255
            }
        }
        pixels.withUnsafeBytes { buf in
            texture.replace(region: MTLRegionMake2D(0, 0, width, height),
                            mipmapLevel: 0,
                            withBytes: buf.baseAddress!,
                            bytesPerRow: width * 4)
        }
        return texture
    }
}
