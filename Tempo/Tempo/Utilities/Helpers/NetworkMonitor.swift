import Foundation
import Network

@Observable
final class NetworkMonitor: @unchecked Sendable {

    private(set) var isConnected: Bool = true
    private(set) var connectionType: NWInterface.InterfaceType?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.tempo.network-monitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.availableInterfaces.first?.type
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
