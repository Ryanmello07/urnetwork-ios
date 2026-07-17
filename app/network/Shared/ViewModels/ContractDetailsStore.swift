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
 * Aggregated contract pairs for one peer client. The aggregation, coalescing,
 * renewal-atomicity, and closing lifecycle all live in the SDK
 * ContractDetailsViewController now (shared by every platform); this row is just
 * the rendered shape.
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

    // the client's last contract closed and the row is being ejected: it is kept
    // briefly (by the SDK view controller) so its circles slide off, then removed
    var closing: Bool = false

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

private class ContractRowsListener: NSObject, SdkContractRowsListenerProtocol {
    private let callback: () -> Void
    init(callback: @escaping () -> Void) {
        self.callback = callback
    }
    func contractRowsChanged() {
        callback()
    }
}

/**
 * Publishes the live, aggregated contract rows for the mode's traffic. All the
 * work — coalescing egress+ingress, holding a renewing contract's slot so a
 * replace is atomic, per-peer aggregation, and the closing/eject lifecycle —
 * is done by the SDK ContractDetailsViewController; this store just maps its rows
 * onto the UI type.
 */
@MainActor
class ContractDetailsStore: ObservableObject {

    let mode: ContractDetailsMode

    @Published private(set) var rows: [ContractClientRow] = []

    private var device: SdkDeviceRemote?
    private var viewController: SdkContractDetailsViewController?
    private var rowsSub: SdkSubProtocol?

    init(mode: ContractDetailsMode) {
        self.mode = mode
    }

    func setup(_ device: SdkDeviceRemote) {
        reset()

        self.device = device
        let vc = device.openContractDetailsViewController()
        self.viewController = vc
        self.rowsSub = vc?.add(ContractRowsListener { [weak self] in
            DispatchQueue.main.async {
                self?.update()
            }
        })
        vc?.start()
        update()
    }

    func reset() {
        rowsSub?.close()
        rowsSub = nil
        viewController?.close()
        viewController = nil
        device = nil
        rows = []
    }

    private func update() {
        guard let vc = self.viewController else {
            return
        }
        let list: SdkContractClientRowList? =
            mode == .client ? vc.getClientContractRows() : vc.getProviderContractRows()

        var newRows: [ContractClientRow] = []
        if let list = list {
            for i in 0..<list.len() {
                guard let r = list.get(i) else {
                    continue
                }
                newRows.append(
                    ContractClientRow(
                        clientId: r.clientId,
                        contractId: r.contractId,
                        companionContractId: r.companionContractId,
                        contractUsedByteCount: r.contractUsedByteCount,
                        contractByteCount: r.contractByteCount,
                        contractBitRate: Int(r.contractBitRate),
                        companionContractUsedByteCount: r.companionContractUsedByteCount,
                        companionContractByteCount: r.companionContractByteCount,
                        companionContractBitRate: Int(r.companionContractBitRate),
                        pairCount: Int(r.pairCount),
                        closing: r.closing
                    )
                )
            }
        }

        if newRows != rows {
            rows = newRows
        }
    }
}
