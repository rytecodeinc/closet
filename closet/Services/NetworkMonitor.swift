//
//  NetworkMonitor.swift
//  closet
//
//  Created by Dan Warner on 1/27/25.
//

import Foundation
import Network
import Combine

/// Monitors network connectivity and publishes connection status
@MainActor
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    @Published var isConnected = false
    @Published var connectionType: NWInterface.InterfaceType?
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    private init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
                
                // Determine connection type
                if path.usesInterfaceType(.wifi) {
                    self?.connectionType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self?.connectionType = .cellular
                } else if path.usesInterfaceType(.wiredEthernet) {
                    self?.connectionType = .wiredEthernet
                } else {
                    self?.connectionType = nil
                }
            }
        }
        monitor.start(queue: queue)
        
        // Set initial state
        let currentPath = monitor.currentPath
        isConnected = currentPath.status == .satisfied
    }
    
    deinit {
        monitor.cancel()
    }
}

