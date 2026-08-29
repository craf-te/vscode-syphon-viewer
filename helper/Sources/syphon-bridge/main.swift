// Receives video from Syphon and writes raw RGBA frames to stdout.
// Control messages arrive as JSON Lines on stdin.
import Foundation
import CoreImage
import Metal
import QuartzCore
import SyphonBridgeCore

let version = "0.1.0"

let transport = StdioTransport()

guard let device = MTLCreateSystemDefaultDevice() else {
    transport.sendControl(Event.error(code: .metalUnavailable,
                                      message: "Metal device unavailable"))
    exit(1)
}

let directory = ServerDirectory()
let source = FrameSource(device: device)
let converter = FrameConverter(context: CIContext(mtlDevice: device))

// Statistics for the last second.
var framesInWindow = 0
var bytesInWindow = 0
var windowStartedAt = CACurrentMediaTime()
var connectedUUID: String?
var sourceSize = (width: 0, height: 0)

func sendServers() {
    transport.sendControl(Event.servers(directory.servers))
}

func disconnect(reason: DisconnectReason) {
    guard let uuid = connectedUUID else { return }
    source.disconnect()
    connectedUUID = nil
    sourceSize = (0, 0)
    transport.sendControl(Event.disconnected(uuid: uuid, reason: reason))
}

func connect(uuid: String) {
    guard let description = directory.rawDescription(for: uuid) else {
        transport.sendControl(Event.error(code: .clientInvalid,
                                          message: "Server not found: \(uuid)"))
        return
    }
    guard source.connect(description: description) else {
        transport.sendControl(Event.error(code: .clientInvalid,
                                          message: "Could not create Syphon client"))
        return
    }
    connectedUUID = uuid
    let name = directory.servers.first { $0.uuid == uuid }?.name ?? ""
    transport.sendControl(Event.connected(uuid: uuid, name: name))
}

source.onTexture = { texture in
    sourceSize = (texture.width, texture.height)
    guard let pixels = converter.convert(texture) else {
        transport.sendControl(Event.error(code: .encodeFailed,
                                          message: "Frame conversion failed"))
        return
    }
    transport.sendFrame(width: texture.width, height: texture.height, pixels: pixels)
    framesInWindow += 1
    bytesInWindow += pixels.count
}

source.onInvalidated = {
    disconnect(reason: .invalid)
}

// Do not fetch frames while the writer is backed up. Throughput settles at
// whatever the machine can carry, so there is no frame rate to configure.
source.canDeliver = { !transport.isBusy }

directory.onChange = { servers in
    sendServers()
    // Report a disconnect if the connected server disappears.
    if let uuid = connectedUUID, !servers.contains(where: { $0.uuid == uuid }) {
        disconnect(reason: .retired)
    }
}

transport.onCommand = { command in
    switch command {
    case .listServers:
        sendServers()
    case .connect(let uuid):
        connect(uuid: uuid)
    case .disconnect:
        disconnect(reason: .requested)
    case .pause:
        source.isPaused = true
    case .resume:
        source.isPaused = false
    case .shutdown:
        source.disconnect()
        exit(0)
    }
}

transport.onStdinClosed = {
    // Exit with the extension host rather than leaving an orphan behind.
    source.disconnect()
    exit(0)
}

// Emit statistics every second, but only while connected.
let statsTimer = Timer(timeInterval: 1.0, repeats: true) { _ in
    guard connectedUUID != nil else {
        framesInWindow = 0
        bytesInWindow = 0
        windowStartedAt = CACurrentMediaTime()
        return
    }
    let now = CACurrentMediaTime()
    let elapsed = max(now - windowStartedAt, 0.001)
    transport.sendControl(Event.stats(
        fps: Double(framesInWindow) / elapsed,
        kbps: Double(bytesInWindow) * 8.0 / 1000.0 / elapsed,
        sourceWidth: sourceSize.width,
        sourceHeight: sourceSize.height
    ))
    framesInWindow = 0
    bytesInWindow = 0
    windowStartedAt = now
}
RunLoop.main.add(statsTimer, forMode: .common)

transport.sendControl(Event.hello(version: version,
                                  pid: ProcessInfo.processInfo.processIdentifier))
directory.start()
sendServers()
transport.startReadingCommands()

RunLoop.main.run()
