import Foundation

/// Owns exclusive writes to stdout and reads JSON Lines from stdin.
/// Frames and control messages share stdout, so a serial queue keeps them ordered.
public final class StdioTransport {
    private let out = FileHandle.standardOutput
    private let writeQueue = DispatchQueue(label: "syphon-bridge.stdout")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Whether the previous frame is still being written.
    /// Used to drop new frames when the consumer cannot keep up.
    private var writeInFlight = false
    private let inFlightLock = NSLock()

    public var isBusy: Bool {
        inFlightLock.lock()
        defer { inFlightLock.unlock() }
        return writeInFlight
    }

    /// Called once a full command line has been read from stdin.
    public var onCommand: ((Command) -> Void)?
    /// Called when stdin closes, which means the extension host is gone.
    public var onStdinClosed: (() -> Void)?

    public init() {}

    public func sendControl<T: Encodable>(_ value: T) {
        guard let json = try? encoder.encode(value) else { return }
        write(FrameCodec.encodeControl(json))
    }

    public func sendFrame(width: Int, height: Int, pixels: Data) {
        let data = FrameCodec.encodeFrame(width: width, height: height, pixels: pixels)
        inFlightLock.lock()
        writeInFlight = true
        inFlightLock.unlock()

        writeQueue.async { [weak self, out] in
            out.write(data)
            guard let self else { return }
            self.inFlightLock.lock()
            self.writeInFlight = false
            self.inFlightLock.unlock()
        }
    }

    public func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    /// Start reading stdin, buffering until a full line arrives.
    public func startReadingCommands() {
        let input = FileHandle.standardInput
        var pending = Data()

        input.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                DispatchQueue.main.async { self.onStdinClosed?() }
                return
            }
            pending.append(chunk)

            while let nl = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<nl]
                pending = pending[pending.index(after: nl)...]
                guard !line.isEmpty else { continue }
                do {
                    let cmd = try self.decoder.decode(Command.self, from: Data(line))
                    DispatchQueue.main.async { self.onCommand?(cmd) }
                } catch {
                    self.sendControl(Event.error(
                        code: .badCommand,
                        message: "Invalid command: \(error.localizedDescription)"))
                }
            }
        }
    }

    private func write(_ data: Data) {
        writeQueue.async { [out] in
            out.write(data)
        }
    }
}
