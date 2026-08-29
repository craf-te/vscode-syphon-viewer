import Foundation

/// Encoder for the stdout protocol.
/// `[len: 4B BE][type: 1B][payload]`, where len counts the type byte.
public enum FrameCodec {
    public static let typeControl: UInt8 = 0x01
    public static let typeFrame: UInt8 = 0x02

    public static func encodeControl(_ json: Data) -> Data {
        var out = Data(capacity: 5 + json.count)
        out.append(bigEndian(UInt32(1 + json.count)))
        out.append(typeControl)
        out.append(json)
        return out
    }

    public static func encodeFrame(width: Int, height: Int, pixels: Data) -> Data {
        var out = Data(capacity: 13 + pixels.count)
        out.append(bigEndian(UInt32(1 + 8 + pixels.count)))
        out.append(typeFrame)
        out.append(bigEndian(UInt32(width)))
        out.append(bigEndian(UInt32(height)))
        out.append(pixels)
        return out
    }

    private static func bigEndian(_ value: UInt32) -> Data {
        Data([
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ])
    }
}
