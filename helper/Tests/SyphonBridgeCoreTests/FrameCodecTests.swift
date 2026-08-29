import XCTest
@testable import SyphonBridgeCore

final class FrameCodecTests: XCTestCase {

    func testEncodeControlProducesSpecifiedBytes() throws {
        let json = Data(#"{"event":"hello"}"#.utf8)
        let out = FrameCodec.encodeControl(json)

        // len counts the type byte
        XCTAssertEqual(out.count, 4 + 1 + json.count)
        XCTAssertEqual(readUInt32BE(out, at: 0), UInt32(1 + json.count))
        XCTAssertEqual(out[4], 0x01)
        XCTAssertEqual(Data(out[5...]), json)
    }

    func testEncodeFrameProducesSpecifiedBytes() throws {
        let pixels = Data([0xFF, 0x00, 0x00, 0xFF])  // one red pixel, RGBA
        let out = FrameCodec.encodeFrame(width: 960, height: 540, pixels: pixels)

        XCTAssertEqual(out.count, 4 + 1 + 4 + 4 + pixels.count)
        XCTAssertEqual(readUInt32BE(out, at: 0), UInt32(1 + 8 + pixels.count))
        XCTAssertEqual(out[4], 0x02)
        XCTAssertEqual(readUInt32BE(out, at: 5), 960)
        XCTAssertEqual(readUInt32BE(out, at: 9), 540)
        XCTAssertEqual(Data(out[13...]), pixels)
    }

    func testEncodeFrameWithEmptyPixels() {
        let out = FrameCodec.encodeFrame(width: 1, height: 1, pixels: Data())
        XCTAssertEqual(readUInt32BE(out, at: 0), 9)
        XCTAssertEqual(out.count, 13)
    }

    func testCommandDecoding() throws {
        let decoder = JSONDecoder()

        XCTAssertEqual(try decoder.decode(Command.self, from: Data(#"{"cmd":"listServers"}"#.utf8)),
                       .listServers)
        XCTAssertEqual(try decoder.decode(Command.self, from: Data(#"{"cmd":"connect","uuid":"abc"}"#.utf8)),
                       .connect(uuid: "abc"))
        XCTAssertEqual(try decoder.decode(Command.self, from: Data(#"{"cmd":"disconnect"}"#.utf8)),
                       .disconnect)
        XCTAssertEqual(try decoder.decode(Command.self, from: Data(#"{"cmd":"pause"}"#.utf8)), .pause)
        XCTAssertEqual(try decoder.decode(Command.self, from: Data(#"{"cmd":"resume"}"#.utf8)), .resume)
        XCTAssertEqual(try decoder.decode(Command.self, from: Data(#"{"cmd":"shutdown"}"#.utf8)), .shutdown)
    }

    func testUnknownCommandThrows() {
        let decoder = JSONDecoder()
        XCTAssertThrowsError(try decoder.decode(Command.self, from: Data(#"{"cmd":"nope"}"#.utf8)))
        // the removed config command is rejected too
        XCTAssertThrowsError(try decoder.decode(Command.self, from: Data(#"{"cmd":"config"}"#.utf8)))
    }

    func testEventEncodingShape() throws {
        let data = try JSONEncoder().encode(Event.connected(uuid: "u1", name: "TD"))
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["event"] as? String, "connected")
        XCTAssertEqual(obj["uuid"] as? String, "u1")
        XCTAssertEqual(obj["name"] as? String, "TD")
    }

    private func readUInt32BE(_ d: Data, at i: Int) -> UInt32 {
        (UInt32(d[i]) << 24) | (UInt32(d[i + 1]) << 16) | (UInt32(d[i + 2]) << 8) | UInt32(d[i + 3])
    }
}
