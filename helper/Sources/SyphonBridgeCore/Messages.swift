import Foundation

/// One Syphon server.
public struct ServerInfo: Codable, Equatable, Sendable {
    public let uuid: String
    public let name: String
    public let appName: String

    public init(uuid: String, name: String, appName: String) {
        self.uuid = uuid
        self.name = name
        self.appName = appName
    }
}

/// A command from the extension host, one JSON object per stdin line.
public enum Command: Equatable, Decodable, Sendable {
    case listServers
    case connect(uuid: String)
    case disconnect
    case pause
    case resume
    case shutdown

    private enum CodingKeys: String, CodingKey {
        case cmd, uuid
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let cmd = try c.decode(String.self, forKey: .cmd)
        switch cmd {
        case "listServers": self = .listServers
        case "connect":     self = .connect(uuid: try c.decode(String.self, forKey: .uuid))
        case "disconnect":  self = .disconnect
        case "pause":       self = .pause
        case "resume":      self = .resume
        case "shutdown":    self = .shutdown
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .cmd, in: c, debugDescription: "Unknown command: \(cmd)")
        }
    }
}

/// Why a connection ended.
public enum DisconnectReason: String, Encodable, Sendable {
    case retired, requested, invalid
}

/// Error categories reported to the extension host.
public enum ErrorCode: String, Encodable, Sendable {
    case metalUnavailable = "metal_unavailable"
    case clientInvalid = "client_invalid"
    case encodeFailed = "encode_failed"
    case badCommand = "bad_command"
}

/// An event sent to stdout as a control message.
public enum Event: Encodable, Sendable {
    case hello(version: String, pid: Int32)
    case servers([ServerInfo])
    case connected(uuid: String, name: String)
    case disconnected(uuid: String, reason: DisconnectReason)
    case error(code: ErrorCode, message: String)
    case stats(fps: Double, kbps: Double, sourceWidth: Int, sourceHeight: Int)

    private enum CodingKeys: String, CodingKey {
        case event, version, pid, servers, uuid, name, reason
        case code, message, fps, kbps, sourceWidth, sourceHeight
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .hello(version, pid):
            try c.encode("hello", forKey: .event)
            try c.encode(version, forKey: .version)
            try c.encode(pid, forKey: .pid)
        case let .servers(list):
            try c.encode("servers", forKey: .event)
            try c.encode(list, forKey: .servers)
        case let .connected(uuid, name):
            try c.encode("connected", forKey: .event)
            try c.encode(uuid, forKey: .uuid)
            try c.encode(name, forKey: .name)
        case let .disconnected(uuid, reason):
            try c.encode("disconnected", forKey: .event)
            try c.encode(uuid, forKey: .uuid)
            try c.encode(reason, forKey: .reason)
        case let .error(code, message):
            try c.encode("error", forKey: .event)
            try c.encode(code, forKey: .code)
            try c.encode(message, forKey: .message)
        case let .stats(fps, kbps, w, h):
            try c.encode("stats", forKey: .event)
            try c.encode(fps, forKey: .fps)
            try c.encode(kbps, forKey: .kbps)
            try c.encode(w, forKey: .sourceWidth)
            try c.encode(h, forKey: .sourceHeight)
        }
    }
}
