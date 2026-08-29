import Foundation
import Syphon

/// Subscribes to the Syphon server list and reports it as ServerInfo values.
/// Syphon's notifications arrive through the main thread's run loop, so call
/// this class from the main thread.
public final class ServerDirectory {

    public var onChange: (([ServerInfo]) -> Void)?

    /// Raw serverDescriptions keyed by UUID, passed to SyphonMetalClient as-is.
    private var descriptions: [String: [String: Any]] = [:]
    private var observers: [NSObjectProtocol] = []

    public init() {}

    public private(set) var servers: [ServerInfo] = []

    public func start() {
        let directory = SyphonServerDirectory.shared()

        // ObjC's SyphonServerAnnounceNotification was renamed in Swift 3 and is
        // exposed as a static member of NSNotification.Name. Writing the old
        // name here does not compile.
        let names: [NSNotification.Name] = [
            .SyphonServerAnnounce,
            .SyphonServerUpdate,
            .SyphonServerRetire,
        ]
        for name in names {
            let token = NotificationCenter.default.addObserver(
                forName: name, object: directory, queue: .main
            ) { [weak self] _ in
                self?.refresh()
            }
            observers.append(token)
        }

        refresh()
    }

    /// The raw serverDescription for a UUID, or nil if it is not present.
    public func rawDescription(for uuid: String) -> [String: Any]? {
        descriptions[uuid]
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func refresh() {
        var infos: [ServerInfo] = []
        var map: [String: [String: Any]] = [:]

        // In Swift, servers holds [String: any NSCoding]. That upcasts to
        // [String: Any] unconditionally, so as? is not needed.
        for entry in SyphonServerDirectory.shared().servers {
            let dict = entry as [String: Any]
            guard let uuid = dict[SyphonServerDescriptionUUIDKey] as? String else { continue }
            let name = dict[SyphonServerDescriptionNameKey] as? String ?? ""
            let appName = dict[SyphonServerDescriptionAppNameKey] as? String ?? ""
            infos.append(ServerInfo(uuid: uuid, name: name, appName: appName))
            map[uuid] = dict
        }

        infos.sort { ($0.appName, $0.name) < ($1.appName, $1.name) }

        let changed = infos != servers
        servers = infos
        descriptions = map
        if changed { onChange?(infos) }
    }
}
