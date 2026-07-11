//
//  NetworkConfig.swift
//  URnetwork
//
//  Default network space values for the official URnetwork server. These are
//  the same values `DeviceManager.initializeNetworkSpace()` used to hardcode
//  inline; naming them here lets the network-server selector (see
//  `NetworkServerSheet`) reset back to these defaults, mirroring how the
//  Android app's per-flavor `BuildConfig.BRINGYOUR_BUNDLE_*` constants work.
//
//  Note: `wallet` is `"circle"` here, not `"solana"` - this is intentionally
//  different from Android's flavors and governs the app's own concept of a
//  wallet, separate from the "Sign in with Solana" wallet-login feature.
//  Do not change this to match Android without confirming what it controls.
//

import Foundation

struct NetworkConfig {
    static let officialHostName = "ur.network"
    static let officialEnvName = "main"
    static let officialLinkHostName = "ur.io"
    static let officialMigrationHostName = "bringyour.com"

    static let envSecret = ""
    static let store = ""
    static let wallet = "circle"
    static let ssoGoogle = false
    static let netExposeServerIps = true
    static let netExposeServerHostNames = true
}
