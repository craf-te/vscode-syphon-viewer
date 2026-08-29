import Foundation
import CoreImage
import Metal

/// Turns an MTLTexture into raw RGBA bytes that can go straight onto a canvas.
///
/// Nothing is scaled or compressed: the source resolution and pixels are
/// delivered as they are. Going through JPEG subsamples chroma, which smears
/// saturated colour across sharp edges — measured at up to 200/255 of error on
/// VJ material.
///
/// The BGRA-to-RGBA swizzle and the colour space conversion are folded into a
/// single CIContext pass on the GPU, so the result is read back only once.
public struct FrameConverter {

    private let context: CIContext
    private let colorSpace: CGColorSpace

    public init(context: CIContext) {
        self.context = context
        self.colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    /// Returns RGBA8 bytes, texture.width * texture.height * 4 long.
    public func convert(_ texture: MTLTexture) -> Data? {
        // Metal textures are top-left origin, CoreImage is bottom-left, so flip.
        let options: [CIImageOption: Any] = [.colorSpace: colorSpace]
        guard var image = CIImage(mtlTexture: texture, options: options) else { return nil }
        image = image.oriented(.downMirrored)

        // Force opaque. ImageData honours the alpha channel verbatim, so any
        // transparency left here would let the canvas background show through.
        image = image.settingAlphaOne(in: image.extent)

        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.origin.x,
                                                       y: -image.extent.origin.y))

        let bounds = CGRect(x: 0, y: 0, width: CGFloat(texture.width), height: CGFloat(texture.height))
        let rowBytes = texture.width * 4
        var out = Data(count: rowBytes * texture.height)

        out.withUnsafeMutableBytes { raw in
            // Asking for .RGBA8 makes the GPU do the swizzle from BGRA too.
            context.render(image,
                           toBitmap: raw.baseAddress!,
                           rowBytes: rowBytes,
                           bounds: bounds,
                           format: .RGBA8,
                           colorSpace: colorSpace)
        }
        return out
    }
}
