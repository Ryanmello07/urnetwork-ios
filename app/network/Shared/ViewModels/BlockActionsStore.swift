//
//  BlockActionsStore.swift
//  URnetwork
//
//  Created by Brien Colwell on 7/8/26.
//

import Foundation
import SwiftUI
import URnetworkSdk

/**
 * A recent routing decision, aggregated per destination cluster
 */
struct BlockActionItem: Identifiable, Equatable {
    let id: String
    let time: Date
    let hosts: [String]
    let ips: [String]
    let block: Bool
    let local: Bool
    /**
     * the deciding override id, when an override determined the decision
     */
    let overrideId: String?
    let hasBlockOverride: Bool
    let hasRouteOverride: Bool
    let packetCount: Int
    let byteCount: Int64

    /**
     * all host values that can be added to a split rule,
     * host names first
     */
    var hostValues: [String] {
        hosts + ips
    }

    /**
     * the host names in the cluster if there are host names
     * ("A, B, C + X IPs"), else the ips, compacted when long
     */
    var displayText: String {
        formatHostClusterText(hosts: hosts, ips: ips)
    }
}

/**
 * A block action override ("split rule")
 */
struct SplitRuleItem: Identifiable, Equatable {
    let id: String
    let hosts: [String]
    let routeLocal: Bool
}

private class BlockActionsListener: NSObject, SdkBlockActionsListenerProtocol {
    private let callback: () -> Void
    init(callback: @escaping () -> Void) {
        self.callback = callback
    }
    func blockActionsChanged() {
        callback()
    }
}

private class BlockActionStatsListener: NSObject, SdkBlockActionStatsListenerProtocol {
    private let callback: () -> Void
    init(callback: @escaping () -> Void) {
        self.callback = callback
    }
    func blockActionStatsChanged() {
        callback()
    }
}

private class BlockActionOverridesListener: NSObject, SdkBlockActionOverridesChangeListenerProtocol {
    private let callback: () -> Void
    init(callback: @escaping () -> Void) {
        self.callback = callback
    }
    func blockActionOverridesChanged(_ blockActionOverrides: SdkBlockActionOverrideList?) {
        callback()
    }
}

/**
 * Publishes the live block action window, block stats, and the
 * block action overrides ("split rules")
 */
@MainActor
class BlockActionsStore: ObservableObject {

    /**
     * newest first
     */
    @Published private(set) var blockActions: [BlockActionItem] = []
    @Published private(set) var splitRules: [SplitRuleItem] = []
    @Published private(set) var allowedCount: Int = 0
    @Published private(set) var blockedCount: Int = 0

    private var device: SdkDeviceRemote?
    private var blockActionViewController: SdkBlockActionViewController?

    private var blockActionsSub: SdkSubProtocol?
    private var blockActionStatsSub: SdkSubProtocol?
    private var overridesSub: SdkSubProtocol?

    /**
     * the sdk override objects backing `splitRules`, used to rebuild
     * the full list on update
     */
    private var sdkOverrides: [SdkBlockActionOverride] = []

    func setup(_ device: SdkDeviceRemote) {
        reset()

        self.device = device

        guard let blockActionViewController = device.openBlockActionViewController() else {
            return
        }
        self.blockActionViewController = blockActionViewController

        self.blockActionsSub = blockActionViewController.add(BlockActionsListener { [weak self] in
            DispatchQueue.main.async {
                self?.updateBlockActions()
            }
        })
        self.blockActionStatsSub = blockActionViewController.add(BlockActionStatsListener { [weak self] in
            DispatchQueue.main.async {
                self?.updateBlockStats()
            }
        })
        self.overridesSub = device.add(BlockActionOverridesListener { [weak self] in
            DispatchQueue.main.async {
                self?.updateOverrides()
            }
        })

        updateBlockActions()
        updateBlockStats()
        updateOverrides()
    }

    func reset() {
        blockActionsSub?.close()
        blockActionsSub = nil
        blockActionStatsSub?.close()
        blockActionStatsSub = nil
        overridesSub?.close()
        overridesSub = nil
        blockActionViewController?.close()
        blockActionViewController = nil
        device = nil

        blockActions = []
        splitRules = []
        sdkOverrides = []
        allowedCount = 0
        blockedCount = 0
    }

    private func updateBlockActions() {
        guard let vc = blockActionViewController else {
            return
        }
        var items: [BlockActionItem] = []
        if let list = vc.getBlockActions() {
            items.reserveCapacity(list.len())
            for i in 0..<list.len() {
                guard let action = list.get(i) else {
                    continue
                }
                items.append(
                    BlockActionItem(
                        id: action.blockActionId?.idStr ?? UUID().uuidString,
                        time: Date(timeIntervalSince1970: TimeInterval(action.time) / 1000.0),
                        hosts: stringListToArray(action.hosts),
                        ips: stringListToArray(action.ips),
                        block: action.block,
                        local: action.local,
                        overrideId: action.overrideId?.idStr,
                        hasBlockOverride: action.blockOverride != nil,
                        hasRouteOverride: action.routeOverride != nil,
                        packetCount: action.packetCount,
                        byteCount: action.byteCount
                    )
                )
            }
        }
        // newest first; only publish when the list actually changed (the SDK
        // re-emits per routing decision, storming observers otherwise)
        let newActions = Array(items.reversed())
        if newActions != blockActions {
            blockActions = newActions
        }
    }

    private func updateBlockStats() {
        guard let vc = blockActionViewController else {
            return
        }
        let stats = vc.getBlockStats()
        let newAllowed = stats?.allowedCount ?? 0
        let newBlocked = stats?.blockedCount ?? 0
        if newAllowed != allowedCount {
            allowedCount = newAllowed
        }
        if newBlocked != blockedCount {
            blockedCount = newBlocked
        }
    }

    private func updateOverrides() {
        guard let device = self.device else {
            return
        }
        var overrides: [SdkBlockActionOverride] = []
        var items: [SplitRuleItem] = []
        if let list = device.getBlockActionOverrides() {
            for i in 0..<list.len() {
                guard let override = list.get(i), let overrideId = override.overrideId else {
                    continue
                }
                overrides.append(override)
                items.append(
                    SplitRuleItem(
                        id: overrideId.idStr,
                        hosts: stringListToArray(override.hosts),
                        routeLocal: override.routeOverride?.local ?? false
                    )
                )
            }
        }
        sdkOverrides = overrides
        if items != splitRules {
            splitRules = items
        }
    }

    /**
     * the split rule matching a block action's applied override, if it still exists
     */
    func splitRule(overrideId: String?) -> SplitRuleItem? {
        guard let overrideId = overrideId else {
            return nil
        }
        return splitRules.first { $0.id == overrideId }
    }

    /**
     * creates a split rule forcing the selected host values to route local
     */
    func createLocalRule(hosts: [String]) {
        guard let device = self.device, !hosts.isEmpty else {
            return
        }
        let override = SdkBlockActionOverride()
        override.overrideId = SdkNewId()
        override.hosts = arrayToStringList(hosts)
        let route = SdkRouteOverride()
        route.local = true
        override.routeOverride = route
        device.add(override)
        updateOverrides()
    }

    /**
     * replaces the host values of an existing split rule
     */
    func updateRule(id: String, hosts: [String]) {
        guard let device = self.device else {
            return
        }
        guard let override = sdkOverrides.first(where: { $0.overrideId?.idStr == id }) else {
            return
        }
        if hosts.isEmpty {
            removeRule(id: id)
            return
        }
        override.hosts = arrayToStringList(hosts)
        let list = SdkBlockActionOverrideList()
        for sdkOverride in sdkOverrides {
            list?.add(sdkOverride)
        }
        device.setBlockActionOverrides(list)
        updateOverrides()
    }

    func removeRule(id: String) {
        guard let device = self.device else {
            return
        }
        guard let override = sdkOverrides.first(where: { $0.overrideId?.idStr == id }) else {
            return
        }
        device.removeBlockActionOverride(override.overrideId)
        updateOverrides()
    }

    private func stringListToArray(_ list: SdkStringList?) -> [String] {
        guard let list = list else {
            return []
        }
        var values: [String] = []
        values.reserveCapacity(list.len())
        for i in 0..<list.len() {
            values.append(list.get(i))
        }
        return values
    }

    private func arrayToStringList(_ values: [String]) -> SdkStringList? {
        let list = SdkStringList()
        for value in values {
            list?.add(value)
        }
        return list
    }
}
