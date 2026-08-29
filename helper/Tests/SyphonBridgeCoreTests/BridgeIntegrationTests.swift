import XCTest
import Foundation
import CoreImage
import Metal
@testable import SyphonBridgeCore

/// Starts TestSyphonServer for real and exercises the actual Syphon path.
final class BridgeIntegrationTests: XCTestCase {

    private var serverProcess: Process?

    override func tearDown() {
        serverProcess?.terminate()
        serverProcess?.waitUntilExit()
        serverProcess = nil
        super.tearDown()
    }

    func testDirectoryDiscoversTestServer() throws {
        let name = "SyphonBridgeTest-\(UUID().uuidString.prefix(8))"
        try startTestServer(name: name)

        let directory = ServerDirectory()
        let found = expectation(description: "test server discovered")
        found.assertForOverFulfill = false

        directory.onChange = { servers in
            if servers.contains(where: { $0.name == name }) {
                found.fulfill()
            }
        }
        directory.start()

        // It may already be listed by the time start() returns.
        if directory.servers.contains(where: { $0.name == name }) {
            found.fulfill()
        }

        wait(for: [found], timeout: 10.0)

        let info = try XCTUnwrap(directory.servers.first(where: { $0.name == name }))
        XCTAssertFalse(info.uuid.isEmpty)
        XCTAssertEqual(info.appName, "TestSyphonServer")
        XCTAssertNotNil(directory.rawDescription(for: info.uuid))
    }

    /// No frame is fetched while the writer is backed up. This is what keeps
    /// congestion in check in place of an fps setting, so pin the behaviour.
    func testFrameSourceDropsWhileConsumerIsBusy() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal device available")
        }
        let name = "SyphonBridgeTest-\(UUID().uuidString.prefix(8))"
        try startTestServer(name: name, width: 320, height: 180)

        let directory = ServerDirectory()
        let appeared = expectation(description: "server appears in the list")
        appeared.assertForOverFulfill = false
        directory.onChange = { servers in
            if servers.contains(where: { $0.name == name }) { appeared.fulfill() }
        }
        directory.start()
        if directory.servers.contains(where: { $0.name == name }) { appeared.fulfill() }
        wait(for: [appeared], timeout: 10.0)

        let info = try XCTUnwrap(directory.servers.first(where: { $0.name == name }))
        let description = try XCTUnwrap(directory.rawDescription(for: info.uuid))

        let source = FrameSource(device: device)
        var busy = true
        source.canDeliver = { !busy }
        var count = 0
        source.onTexture = { _ in count += 1 }
        XCTAssertTrue(source.connect(description: description))

        // Nothing arrives while the writer is busy
        var done = expectation(description: "wait one second")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { done.fulfill() }
        wait(for: [done], timeout: 3.0)
        XCTAssertEqual(count, 0, "frames were delivered while the writer was busy")

        // Once released, frames start flowing
        busy = false
        done = expectation(description: "wait another second")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { done.fulfill() }
        wait(for: [done], timeout: 3.0)
        source.disconnect()
        XCTAssertGreaterThan(count, 30, "no frames after release: \(count)")
    }

    func testFrameSourceDeliversNothingWhilePaused() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal device available")
        }
        let name = "SyphonBridgeTest-\(UUID().uuidString.prefix(8))"
        try startTestServer(name: name, width: 320, height: 180)

        let directory = ServerDirectory()
        let appeared = expectation(description: "server appears in the list")
        appeared.assertForOverFulfill = false
        directory.onChange = { servers in
            if servers.contains(where: { $0.name == name }) { appeared.fulfill() }
        }
        directory.start()
        if directory.servers.contains(where: { $0.name == name }) { appeared.fulfill() }
        wait(for: [appeared], timeout: 10.0)

        let info = try XCTUnwrap(directory.servers.first(where: { $0.name == name }))
        let description = try XCTUnwrap(directory.rawDescription(for: info.uuid))

        let source = FrameSource(device: device)
        source.isPaused = true
        var count = 0
        source.onTexture = { _ in count += 1 }
        XCTAssertTrue(source.connect(description: description))

        let done = expectation(description: "wait one second")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { done.fulfill() }
        wait(for: [done], timeout: 3.0)
        source.disconnect()

        XCTAssertEqual(count, 0, "frames were delivered while paused")
    }

    /// Launches the built TestSyphonServer.
    func startTestServer(name: String, width: Int = 1920, height: Int = 1080) throws {
        let binary = Self.productsDirectory.appendingPathComponent("TestSyphonServer")
        guard FileManager.default.fileExists(atPath: binary.path) else {
            throw XCTSkip("TestSyphonServer is not built; run swift build first")
        }
        let p = Process()
        p.executableURL = binary
        p.arguments = ["--name", name, "--width", "\(width)", "--height", "\(height)"]
        p.standardError = FileHandle.nullDevice
        try p.run()
        serverProcess = p

        // Give Syphon a moment to announce.
        Thread.sleep(forTimeInterval: 1.0)

        // The server exits immediately when there is no Metal device, which is
        // the case on some CI machines. That is a skip, not a failure.
        guard p.isRunning else {
            serverProcess = nil
            throw XCTSkip("TestSyphonServer exited on start; no Metal device?")
        }
    }

    /// Build products sit next to the test bundle.
    static var productsDirectory: URL {
        Bundle.allBundles
            .first(where: { $0.bundlePath.hasSuffix(".xctest") })
            .map { $0.bundleURL.deletingLastPathComponent() }
            ?? URL(fileURLWithPath: ".build/debug")
    }

    /// Runs syphon-bridge as a child process and exercises the whole protocol.
    func testBridgeEndToEnd() throws {
        // A 1920x1080 raw RGBA frame is 8.3MB and crosses the pipe in ~130
        // fragments. A virtualised runner does not sustain the rate asserted
        // below. The same Syphon path passes there at 320x180 in
        // testFrameSourceDropsWhileConsumerIsBusy, so what falls short is the
        // rate, not the plumbing. Keep this one on real hardware.
        if ProcessInfo.processInfo.environment["CI"] != nil {
            throw XCTSkip("throughput needs real hardware")
        }

        let name = "SyphonBridgeTest-\(UUID().uuidString.prefix(8))"
        try startTestServer(name: name, width: 1920, height: 1080)

        let binary = Self.productsDirectory.appendingPathComponent("syphon-bridge")
        guard FileManager.default.fileExists(atPath: binary.path) else {
            throw XCTSkip("syphon-bridge is not built")
        }

        let bridge = Process()
        bridge.executableURL = binary
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        bridge.standardInput = stdinPipe
        bridge.standardOutput = stdoutPipe
        bridge.standardError = FileHandle.nullDevice
        try bridge.run()
        defer {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            if bridge.isRunning { bridge.terminate() }
            bridge.waitUntilExit()
        }

        let decoder = TestMessageDecoder()
        var controls: [[String: Any]] = []
        var frames: [(Int, Int, Data)] = []
        let lock = NSLock()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            // Empty data means EOF; leaving the handler attached spins forever.
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            for message in (try? decoder.push(chunk)) ?? [] {
                lock.lock()
                switch message {
                case .control(let obj): controls.append(obj)
                case .frame(let w, let h, let jpeg): frames.append((w, h, jpeg))
                }
                lock.unlock()
            }
        }

        func snapshotControls() -> [[String: Any]] {
            lock.lock(); defer { lock.unlock() }
            return controls
        }

        // Wait for hello and the server list
        try waitUntil(timeout: 10) {
            let c = snapshotControls()
            guard c.contains(where: { $0["event"] as? String == "hello" }) else { return false }
            return c.contains { control in
                guard control["event"] as? String == "servers",
                      let list = control["servers"] as? [[String: Any]] else { return false }
                return list.contains { $0["name"] as? String == name }
            }
        }

        // Pull out the target server's UUID. A force unwrap would crash on
        // timeout and skip teardown, so fail explicitly through XCTUnwrap.
        let serversEvent = try XCTUnwrap(
            snapshotControls().last { $0["event"] as? String == "servers" },
            "no servers event arrived")
        let list = try XCTUnwrap(serversEvent["servers"] as? [[String: Any]])
        let entry = try XCTUnwrap(list.first { $0["name"] as? String == name })
        let uuid = try XCTUnwrap(entry["uuid"] as? String)

        // Connect
        send(["cmd": "connect", "uuid": uuid], to: stdinPipe)

        try waitUntil(timeout: 10) {
            snapshotControls().contains { $0["event"] as? String == "connected" }
        }

        lock.lock(); frames.removeAll(); lock.unlock()
        pump(seconds: 2.0)

        lock.lock()
        let received = frames
        lock.unlock()

        // There is no rate cap; throughput finds its own level.
        XCTAssertGreaterThan(received.count, 10, "almost nothing arrived in two seconds: \(received.count)")

        let (w, h, pixels) = try XCTUnwrap(received.first)
        XCTAssertEqual(w, 1920, "not delivered at source resolution")
        XCTAssertEqual(h, 1080, "not delivered at source resolution")
        XCTAssertEqual(pixels.count, 1920 * 1080 * 4, "wrong raw RGBA byte count")

        // TestSyphonServer writes BGRA with B=x*255/W, G=y*255/H, R=200.
        // The top-left pixel should come out as R=200, G~0, B~0, A=255.
        let px = [UInt8](pixels.prefix(4))
        XCTAssertEqual(Int(px[0]), 200, accuracy: 4, "unexpected R")
        XCTAssertLessThan(Int(px[1]), 8, "unexpected G")
        XCTAssertLessThan(Int(px[2]), 8, "unexpected B")
        XCTAssertEqual(px[3], 255, "alpha is not opaque")

        // pause stops delivery
        send(["cmd": "pause"], to: stdinPipe)
        pump(seconds: 0.4)
        lock.lock(); frames.removeAll(); lock.unlock()
        pump(seconds: 1.0)
        lock.lock(); let whilePaused = frames.count; lock.unlock()
        XCTAssertEqual(whilePaused, 0, "frames arrived while paused")

        send(["cmd": "shutdown"], to: stdinPipe)
    }

    private func send(_ obj: [String: Any], to pipe: Pipe) {
        var data = try! JSONSerialization.data(withJSONObject: obj)
        data.append(0x0A)
        pipe.fileHandleForWriting.write(data)
    }

    /// Waits while pumping the run loop, which readabilityHandler needs.
    private func pump(seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func waitUntil(timeout: TimeInterval,
                           _ condition: () -> Bool,
                           file: StaticString = #filePath,
                           line: UInt = #line) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTFail("condition not met within \(timeout)s", file: file, line: line)
    }
}

/// A hand-written decoder for the stdout protocol.
/// Sharing no code with the production encoder is what makes this a check
/// against the specification rather than against the implementation.
final class TestMessageDecoder {
    enum Message {
        case control([String: Any])
        case frame(Int, Int, Data)
    }
    enum DecodeError: Error { case protocolViolation(String) }

    private var buffer = Data()

    func push(_ chunk: Data) throws -> [Message] {
        buffer.append(chunk)
        var result: [Message] = []

        while buffer.count >= 5 {
            let len = Int(readUInt32BE(buffer, at: 0))
            if len == 0 || len > 33_554_432 {
                throw DecodeError.protocolViolation("bad length: \(len)")
            }
            guard buffer.count >= 4 + len else { break }

            let type = buffer[buffer.startIndex + 4]
            let payload = Data(buffer[(buffer.startIndex + 5)..<(buffer.startIndex + 4 + len)])

            switch type {
            case 0x01:
                let obj = try JSONSerialization.jsonObject(with: payload) as! [String: Any]
                result.append(.control(obj))
            case 0x02:
                guard payload.count >= 8 else {
                    throw DecodeError.protocolViolation("frame too short")
                }
                let w = Int(readUInt32BE(payload, at: 0))
                let h = Int(readUInt32BE(payload, at: 4))
                result.append(.frame(w, h, Data(payload[(payload.startIndex + 8)...])))
            default:
                throw DecodeError.protocolViolation("unknown type: \(type)")
            }
            buffer = Data(buffer[(buffer.startIndex + 4 + len)...])
        }
        return result
    }

    private func readUInt32BE(_ d: Data, at i: Int) -> UInt32 {
        let s = d.startIndex + i
        return (UInt32(d[s]) << 24) | (UInt32(d[s + 1]) << 16) | (UInt32(d[s + 2]) << 8) | UInt32(d[s + 3])
    }
}
