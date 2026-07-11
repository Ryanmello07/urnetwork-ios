//
//  DnsSettingsStore.swift
//  URnetwork
//
//  Created by Brien Colwell on 7/8/26.
//

import Foundation
import SwiftUI
import URnetworkSdk

/**
 * Editable snapshot of the device dns resolver settings
 */
struct DnsSettings: Equatable {
    var enableRemoteDoh: Bool = false
    var enableLocalDoh: Bool = false
    var enableRemoteDns: Bool = false
    var enableLocalDns: Bool = false
    var enableFallback: Bool = false

    var remoteDohUrlsIpv4: [String] = []
    var remoteDohUrlsIpv6: [String] = []
    var localDohUrlsIpv4: [String] = []
    var localDohUrlsIpv6: [String] = []
    var remoteDnsIpv4: [String] = []
    var remoteDnsIpv6: [String] = []
    var localDnsIpv4: [String] = []
    var localDnsIpv6: [String] = []

    /**
     * summary states shown in the connect drawer
     */
    var dohEnabled: Bool {
        enableRemoteDoh || enableLocalDoh
    }
    var unencryptedDnsEnabled: Bool {
        enableRemoteDns || enableLocalDns
    }
    var localDnsEnabled: Bool {
        enableLocalDoh || enableLocalDns
    }
    var localDnsFallbackEnabled: Bool {
        enableFallback
    }

    init() {}

    init(_ settings: SdkDnsResolverSettings) {
        enableRemoteDoh = settings.enableRemoteDoh
        enableLocalDoh = settings.enableLocalDoh
        enableRemoteDns = settings.enableRemoteDns
        enableLocalDns = settings.enableLocalDns
        enableFallback = settings.enableFallback

        remoteDohUrlsIpv4 = Self.stringListToArray(settings.remoteDohUrlsIpv4)
        remoteDohUrlsIpv6 = Self.stringListToArray(settings.remoteDohUrlsIpv6)
        localDohUrlsIpv4 = Self.stringListToArray(settings.localDohUrlsIpv4)
        localDohUrlsIpv6 = Self.stringListToArray(settings.localDohUrlsIpv6)
        remoteDnsIpv4 = Self.stringListToArray(settings.remoteDnsIpv4)
        remoteDnsIpv6 = Self.stringListToArray(settings.remoteDnsIpv6)
        localDnsIpv4 = Self.stringListToArray(settings.localDnsIpv4)
        localDnsIpv6 = Self.stringListToArray(settings.localDnsIpv6)
    }

    func toSdk() -> SdkDnsResolverSettings {
        let settings = SdkDnsResolverSettings()
        settings.enableRemoteDoh = enableRemoteDoh
        settings.enableLocalDoh = enableLocalDoh
        settings.enableRemoteDns = enableRemoteDns
        settings.enableLocalDns = enableLocalDns
        settings.enableFallback = enableFallback

        settings.remoteDohUrlsIpv4 = Self.arrayToStringList(remoteDohUrlsIpv4)
        settings.remoteDohUrlsIpv6 = Self.arrayToStringList(remoteDohUrlsIpv6)
        settings.localDohUrlsIpv4 = Self.arrayToStringList(localDohUrlsIpv4)
        settings.localDohUrlsIpv6 = Self.arrayToStringList(localDohUrlsIpv6)
        settings.remoteDnsIpv4 = Self.arrayToStringList(remoteDnsIpv4)
        settings.remoteDnsIpv6 = Self.arrayToStringList(remoteDnsIpv6)
        settings.localDnsIpv4 = Self.arrayToStringList(localDnsIpv4)
        settings.localDnsIpv6 = Self.arrayToStringList(localDnsIpv6)
        return settings
    }

    private static func stringListToArray(_ list: SdkStringList?) -> [String] {
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

    private static func arrayToStringList(_ values: [String]) -> SdkStringList? {
        let list = SdkStringList()
        for value in values {
            list?.add(value)
        }
        return list
    }
}

private class DnsResolverSettingsListener: NSObject, SdkDnsResolverSettingsChangeListenerProtocol {
    private let callback: () -> Void
    init(callback: @escaping () -> Void) {
        self.callback = callback
    }
    func dnsResolverSettingsChanged(_ dnsResolverSettings: SdkDnsResolverSettings?) {
        callback()
    }
}

/**
 * Publishes the device dns resolver settings and applies edits
 */
@MainActor
class DnsSettingsStore: ObservableObject {

    @Published private(set) var settings: DnsSettings? = nil

    private var device: SdkDeviceRemote?
    private var settingsSub: SdkSubProtocol?

    func setup(_ device: SdkDeviceRemote) {
        reset()

        self.device = device
        self.settingsSub = device.add(DnsResolverSettingsListener { [weak self] in
            DispatchQueue.main.async {
                self?.update()
            }
        })

        update()
    }

    func reset() {
        settingsSub?.close()
        settingsSub = nil
        device = nil
        settings = nil
    }

    private func update() {
        guard let device = self.device else {
            return
        }
        if let sdkSettings = device.getDnsResolverSettings() {
            settings = DnsSettings(sdkSettings)
        } else {
            settings = nil
        }
    }

    func apply(_ newSettings: DnsSettings) {
        guard let device = self.device else {
            return
        }
        device.setDnsResolverSettings(newSettings.toSdk())
        update()
    }
}
