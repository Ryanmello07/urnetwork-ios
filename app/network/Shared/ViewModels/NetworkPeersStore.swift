//
//  NetworkPeersStore.swift
//  URnetwork
//
//  Created by Brien Colwell on 7/8/26.
//

import Foundation
import SwiftUI
import URnetworkSdk

/**
 * A connected peer of this device on the network
 */
struct NetworkPeerItem: Identifiable, Equatable {
    let clientId: SdkId
    let deviceName: String
    let deviceSpec: String
    let provideEnabled: Bool

    var id: String {
        clientId.idStr
    }

    // compare by the stable string id — SdkId is an SDK object compared by
    // identity, which differs on every rebuild and would defeat the dedup
    static func == (lhs: NetworkPeerItem, rhs: NetworkPeerItem) -> Bool {
        lhs.id == rhs.id
            && lhs.deviceName == rhs.deviceName
            && lhs.deviceSpec == rhs.deviceSpec
            && lhs.provideEnabled == rhs.provideEnabled
    }

    /**
     * the device name, or the device spec if the name is not available
     */
    var displayName: String {
        if !deviceName.isEmpty {
            return deviceName
        }
        if !deviceSpec.isEmpty {
            return deviceSpec
        }
        return clientId.idStr
    }

    /**
     * a direct connection to this peer device
     */
    func toConnectLocation() -> SdkConnectLocation {
        let location = SdkConnectLocation()
        let locationId = SdkConnectLocationId()
        locationId.clientId = clientId
        location.connectLocationId = locationId
        location.name = displayName
        return location
    }
}

private class PeersListener: NSObject, SdkPeersListenerProtocol {
    private let callback: () -> Void
    init(callback: @escaping () -> Void) {
        self.callback = callback
    }
    func peersChanged(_ peers: SdkNetworkPeerList?) {
        callback()
    }
}

/**
 * Publishes the connected network peers with provide enabled.
 *
 * Uses the change listener plus one initial get — no polling. Devices
 * without a provider have no network peers and the list stays empty.
 */
@MainActor
class NetworkPeersStore: ObservableObject {

    @Published private(set) var connectedProvidePeers: [NetworkPeerItem] = []

    private var device: SdkDeviceRemote?
    private var peerViewController: SdkPeerViewController?
    private var peersSub: SdkSubProtocol?

    func setup(_ device: SdkDeviceRemote) {
        reset()

        self.device = device
        // the SDK peer view controller already filters to connected + provide-enabled peers
        let vc = device.openPeerViewController()
        self.peerViewController = vc
        self.peersSub = vc?.add(PeersListener { [weak self] in
            DispatchQueue.main.async {
                self?.update()
            }
        })
        vc?.start()
    }

    func reset() {
        peersSub?.close()
        peersSub = nil
        peerViewController?.close()
        peerViewController = nil
        device = nil
        connectedProvidePeers = []
    }

    private func update() {
        guard let vc = self.peerViewController else {
            return
        }
        var peers: [NetworkPeerItem] = []
        if let connected = vc.getPeers() {
            for i in 0..<connected.len() {
                guard let peer = connected.get(i), let clientId = peer.clientId else {
                    continue
                }
                peers.append(
                    NetworkPeerItem(
                        clientId: clientId,
                        deviceName: peer.deviceName,
                        deviceSpec: peer.deviceSpec,
                        provideEnabled: peer.provideEnabled
                    )
                )
            }
        }
        // only publish when the peer set actually changed
        if peers != connectedProvidePeers {
            connectedProvidePeers = peers
        }
    }
}
