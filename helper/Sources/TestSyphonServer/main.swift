// A Syphon server for tests: publishes a known pattern at 60fps.
// Lets the integration tests run without any external app.
import Foundation
import Metal
import Syphon

func argValue(_ key: String, default def: String) -> String {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: key), i + 1 < args.count else { return def }
    return args[i + 1]
}

let name = argValue("--name", default: "SyphonBridgeTest")
let width = Int(argValue("--width", default: "1920")) ?? 1920
let height = Int(argValue("--height", default: "1080")) ?? 1080

guard let device = MTLCreateSystemDefaultDevice(),
      let queue = device.makeCommandQueue() else {
    FileHandle.standardError.write(Data("Metal device unavailable\n".utf8))
    exit(1)
}

let descriptor = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
guard let texture = device.makeTexture(descriptor: descriptor) else {
    FileHandle.standardError.write(Data("Could not create texture\n".utf8))
    exit(1)
}

// Write the gradient once.
var pixels = [UInt8](repeating: 0, count: width * height * 4)
for y in 0..<height {
    for x in 0..<width {
        let i = (y * width + x) * 4
        pixels[i]     = UInt8((x * 255) / width)
        pixels[i + 1] = UInt8((y * 255) / height)
        pixels[i + 2] = 200
        pixels[i + 3] = 255
    }
}
pixels.withUnsafeBytes { buf in
    texture.replace(region: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0, withBytes: buf.baseAddress!, bytesPerRow: width * 4)
}

let server = SyphonMetalServer(name: name, device: device, options: nil)
FileHandle.standardError.write(Data("TestSyphonServer started: \(name) \(width)x\(height)\n".utf8))

let region = NSMakeRect(0, 0, CGFloat(width), CGFloat(height))
let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
    guard let cb = queue.makeCommandBuffer() else { return }
    server.publishFrameTexture(texture, on: cb, imageRegion: region, flipped: false)
    cb.commit()
}
RunLoop.main.add(timer, forMode: .common)

signal(SIGTERM) { _ in exit(0) }
signal(SIGINT) { _ in exit(0) }

RunLoop.main.run()
