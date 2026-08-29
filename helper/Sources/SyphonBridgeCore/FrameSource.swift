import Foundation
import Metal
import Syphon

/// Holds a SyphonMetalClient and delivers only the frames that get through.
///
/// Syphon is pull-based: newFrameHandler only announces that a frame exists.
/// Skipping one means returning without calling newFrameImage(), so no texture
/// is ever created and a dropped frame costs no GPU work at all.
public final class FrameSource {

    /// While this returns false, no frame is fetched.
    /// Used to drop frames while the writer is backed up. The check runs before
    /// the texture is created, so a dropped frame costs no GPU work.
    public var canDeliver: (() -> Bool)?
    /// While true, no frame is delivered.
    public var isPaused: Bool = false
    /// Receives frames that got through. Called on the main thread.
    public var onTexture: ((MTLTexture) -> Void)?
    /// Called when the client becomes invalid.
    public var onInvalidated: (() -> Void)?

    private let device: MTLDevice
    private var client: SyphonMetalClient?

    public init(device: MTLDevice) {
        self.device = device
    }

    public var isConnected: Bool { client != nil }

    /// Connect using a raw serverDescription. Returns true on success.
    @discardableResult
    public func connect(description: [String: Any]) -> Bool {
        disconnect()

        // The ObjC init is not annotated nullable, so Swift imports it as
        // non-optional. Failure has to be detected through isValid.
        let newClient = SyphonMetalClient(
            serverDescription: description,
            device: device,
            options: nil
        ) { [weak self] _ in
            self?.handleNewFrame()
        }
        guard newClient.isValid else { return false }
        client = newClient
        return true
    }

    public func disconnect() {
        client?.stop()
        client = nil
    }

    private func handleNewFrame() {
        guard !isPaused, let client else { return }

        guard client.isValid else {
            disconnect()
            onInvalidated?()
            return
        }

        // Drop this frame if the writer is backed up. Letting throughput find
        // its own level beats a hard-coded cap, and needs no configuration.
        if let canDeliver, !canDeliver() { return }

        // Only now is the texture fetched. Dropped frames never reach this line.
        guard let texture = client.newFrameImage() else { return }
        onTexture?(texture)
    }
}
