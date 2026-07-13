//
//  ContractDetailsStore.swift
//  URnetwork
//
//  Created by Brien Colwell on 7/8/26.
//

import Foundation
import SwiftUI
import URnetworkSdk

/**
 * Aggregated contract pairs for one peer client
 */
struct ContractClientRow: Identifiable, Equatable {
    let clientId: String

    // signatures of the client's active contracts; a change means a contract
    // was replaced, which swaps the circle rather than just resizing it
    var contractId: String = ""
    var companionContractId: String = ""

    var contractUsedByteCount: Int64 = 0
    var contractByteCount: Int64 = 0
    var contractBitRate: Int = 0

    var companionContractUsedByteCount: Int64 = 0
    var companionContractByteCount: Int64 = 0
    var companionContractBitRate: Int = 0

    var pairCount: Int = 0

    var id: String { clientId }

    var isActive: Bool {
        0 < contractBitRate || 0 < companionContractBitRate
    }
}

enum ContractDetailsMode {
    /**
     * contracts for this device's own traffic
     */
    case client
    /**
     * contracts for traffic relayed for remote clients
     */
    case provider
}

private class ContractDetailsListener: NSObject, SdkContractDetailsChangeListenerProtocol {
    private let callback: () -> Void
    init(callback: @escaping () -> Void) {
        self.callback = callback
    }
    func contractDetailsChanged(_ contractDetails: SdkContractDetails?) {
        callback()
    }
}

/**
 * Publishes the live contract details grouped per peer client id.
 * Egress and ingress contract pairs are merged into one row per peer.
 */
@MainActor
class ContractDetailsStore: ObservableObject {

    let mode: ContractDetailsMode

    @Published private(set) var rows: [ContractClientRow] = []

    private var device: SdkDeviceRemote?
    private var egressSub: SdkSubProtocol?
    private var ingressSub: SdkSubProtocol?

    /**
     * keeps row order stable across updates: clients keep their
     * first-seen position, new clients append
     */
    private var clientOrder: [String: Int] = [:]

    init(mode: ContractDetailsMode) {
        self.mode = mode
    }

    func setup(_ device: SdkDeviceRemote) {
        reset()

        self.device = device

        let listener = { [weak self] in
            ContractDetailsListener {
                DispatchQueue.main.async {
                    self?.update()
                }
            }
        }

        switch mode {
        case .client:
            egressSub = device.addEgressContractDetailsChangeListener(listener())
            ingressSub = device.addIngressContractDetailsChangeListener(listener())
        case .provider:
            egressSub = device.addProviderEgressContractDetailsChangeListener(listener())
            ingressSub = device.addProviderIngressContractDetailsChangeListener(listener())
        }

        update()
    }

    func reset() {
        egressSub?.close()
        egressSub = nil
        ingressSub?.close()
        ingressSub = nil
        device = nil
        rows = []
        clientOrder = [:]
    }

    private func update() {
        guard let device = self.device else {
            return
        }

        let egress: SdkContractDetailsList?
        let ingress: SdkContractDetailsList?
        switch mode {
        case .client:
            egress = device.getEgressContractDetails()
            ingress = device.getIngressContractDetails()
        case .provider:
            egress = device.getProviderEgressContractDetails()
            ingress = device.getProviderIngressContractDetails()
        }

        let ownClientId = device.getClientId()?.idStr

        var rowsByClient: [String: ContractClientRow] = [:]
        var contractIdsByClient: [String: [String]] = [:]
        var companionIdsByClient: [String: [String]] = [:]

        let merge = { (list: SdkContractDetailsList?) in
            guard let list = list else {
                return
            }
            for i in 0..<list.len() {
                guard let details = list.get(i) else {
                    continue
                }
                let clientId = Self.peerClientId(details, ownClientId: ownClientId)
                var row = rowsByClient[clientId] ?? ContractClientRow(clientId: clientId)
                row.contractUsedByteCount += details.contractUsedByteCount
                row.contractByteCount += details.contractByteCount
                row.contractBitRate += details.contractBitRate
                row.companionContractUsedByteCount += details.companionContractUsedByteCount
                row.companionContractByteCount += details.companionContractByteCount
                row.companionContractBitRate += details.companionContractBitRate
                row.pairCount += 1
                rowsByClient[clientId] = row
                if let cid = details.contractId?.idStr {
                    contractIdsByClient[clientId, default: []].append(cid)
                }
                if let ccid = details.companionContractId?.idStr {
                    companionIdsByClient[clientId, default: []].append(ccid)
                }
            }
        }
        merge(egress)
        merge(ingress)

        // newest first: newly seen clients are prepended to the top, existing
        // clients keep their relative order
        for clientId in rowsByClient.keys {
            if clientOrder[clientId] == nil {
                clientOrder[clientId] = clientOrder.count
            }
        }
        let newRows = rowsByClient.values.map { row -> ContractClientRow in
            var r = row
            r.contractId = (contractIdsByClient[row.clientId] ?? []).sorted().joined(separator: ",")
            r.companionContractId = (companionIdsByClient[row.clientId] ?? []).sorted().joined(separator: ",")
            return r
        }.sorted {
            (clientOrder[$0.clientId] ?? 0) > (clientOrder[$1.clientId] ?? 0)
        }
        // egress and ingress listeners both call update(); only publish when the
        // aggregated rows actually changed to avoid redundant re-renders
        if newRows != rows {
            rows = newRows
        }
    }

    /**
     * the peer end of the contract transfer path
     */
    private static func peerClientId(_ details: SdkContractDetails, ownClientId: String?) -> String {
        if let path = details.contractTransferPath {
            let sourceId = path.sourceId?.idStr
            let destinationId = path.destinationId?.idStr
            if let ownClientId = ownClientId {
                if sourceId == ownClientId, let destinationId = destinationId {
                    return destinationId
                }
                if destinationId == ownClientId, let sourceId = sourceId {
                    return sourceId
                }
            }
            if let destinationId = destinationId {
                return destinationId
            }
            if let sourceId = sourceId {
                return sourceId
            }
        }
        if let contractId = details.contractId {
            return contractId.idStr
        }
        return String(localized: "unknown")
    }
}
