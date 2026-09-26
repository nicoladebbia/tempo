//
// NetworkStatus.swift
// Tempo
//
// Live "are we online?" for screens that can't work without a connection
// (barcode lookup hits Open Food Facts). NWPathMonitor, main-actor state.
//

import Foundation
import Network
import Observation

@MainActor
@Observable
final class NetworkStatus {
    /// UI tests launch with this to see the offline paths without cutting the network.
    static let simulateOfflineArgument = "--uitesting-simulate-offline"

    private(set) var isOffline = false

    /// Updates `isOffline` until the calling task is cancelled (use from `.task`).
    func monitor() async {
        if ProcessInfo.processInfo.arguments.contains(Self.simulateOfflineArgument) {
            isOffline = true
            return
        }
        let monitor = NWPathMonitor()
        let paths = AsyncStream<NWPath.Status> { continuation in
            monitor.pathUpdateHandler = { continuation.yield($0.status) }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "app.tempo.network-status"))
        }
        for await status in paths {
            isOffline = status != .satisfied
        }
    }
}
